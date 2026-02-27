package main

import (
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/oschwald/maxminddb-golang"
)

// MaxMind 数据库解析结构
type CityRecord struct {
	City struct {
		Names map[string]string `maxminddb:"names"`
	} `maxminddb:"city"`
	Continent struct {
		Code  string            `maxminddb:"code"`
		Names map[string]string `maxminddb:"names"`
	} `maxminddb:"continent"`
	Country struct {
		IsoCode string            `maxminddb:"iso_code"`
		Names   map[string]string `maxminddb:"names"`
	} `maxminddb:"country"`
	Location struct {
		AccuracyRadius uint16  `maxminddb:"accuracy_radius"`
		Latitude       float64 `maxminddb:"latitude"`
		Longitude      float64 `maxminddb:"longitude"`
		TimeZone       string  `maxminddb:"time_zone"`
	} `maxminddb:"location"`
	Postal struct {
		Code string `maxminddb:"code"`
	} `maxminddb:"postal"`
	RegisteredCountry struct {
		IsoCode string            `maxminddb:"iso_code"`
		Names   map[string]string `maxminddb:"names"`
	} `maxminddb:"registered_country"`
	Subdivisions []struct {
		IsoCode string            `maxminddb:"iso_code"`
		Names   map[string]string `maxminddb:"names"`
	} `maxminddb:"subdivisions"`
}

type ASNRecord struct {
	AutonomousSystemNumber       uint   `maxminddb:"autonomous_system_number"`
	AutonomousSystemOrganization string `maxminddb:"autonomous_system_organization"`
}

// API 输出格式
type FlatResponse struct {
	IP                    string   `json:"ip"`
	ASN                   *uint    `json:"asn,omitempty"`
	Org                   string   `json:"org,omitempty"`
	ContinentCode         string   `json:"continent_code,omitempty"`
	Continent             string   `json:"continent,omitempty"`
	CountryCode           string   `json:"country_code,omitempty"`
	Country               string   `json:"country,omitempty"`
	RegisteredCountryCode string   `json:"registered_country_code,omitempty"`
	RegisteredCountry     string   `json:"registered_country,omitempty"`
	RegionCode            string   `json:"region_code,omitempty"`
	Region                string   `json:"region,omitempty"`
	City                  string   `json:"city,omitempty"`
	PostalCode            string   `json:"postal_code,omitempty"`
	Longitude             *float64 `json:"longitude,omitempty"`
	Latitude              *float64 `json:"latitude,omitempty"`
	AccuracyRadius        *uint16  `json:"accuracy_radius,omitempty"`
	Offset                *int     `json:"offset,omitempty"`
	TimeZone              string   `json:"time_zone,omitempty"`
}

var (
	cityDatabase  *maxminddb.Reader
	asnDatabase   *maxminddb.Reader
	timeZoneCache sync.Map     // 时区缓存
	databaseMutex sync.RWMutex // 读写锁
	dbDir         = "./db"
)

// 下载文件的通用函数
func downloadFile(filePath string, fileUrl string) error {
	log.Printf("Downloading %s.\n", filePath)
	response, err := http.Get(fileUrl)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	outputFile, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer outputFile.Close()

	_, err = io.Copy(outputFile, response.Body)
	return err
}

func ensureDatabaseExists(fileName string, fileUrl string) {
	if _, err := os.Stat(fileName); os.IsNotExist(err) {
		log.Printf("Database %s not found. Starting download.\n", fileName)
		if err := downloadFile(fileName, fileUrl); err != nil {
			log.Fatalf("Failed to download %s: %v", fileName, err)
		}
		log.Printf("Successfully downloaded %s\n", fileName)
	}
}

// 并发缓存的获取时区
func getCachedTimeLocation(tzName string) (*time.Location, error) {
	// 从内存读取
	if loc, ok := timeZoneCache.Load(tzName); ok {
		return loc.(*time.Location), nil
	}
	// 内存没有则去系统读取并存入缓存
	loc, err := time.LoadLocation(tzName)
	if err == nil {
		timeZoneCache.Store(tzName, loc)
	}
	return loc, err
}

// 热重载更新数据库
func updateDatabases() {
	log.Println("Database update begins.")

	cityTmp := filepath.Join(dbDir, "City.mmdb.tmp")
	asnTmp := filepath.Join(dbDir, "ASN.mmdb.tmp")
	cityFinal := filepath.Join(dbDir, "City.mmdb")
	asnFinal := filepath.Join(dbDir, "ASN.mmdb")

	// 下载新文件到临时路径
	if err := downloadFile(cityTmp, "https://github.com/xjasonlyu/maxmind-geoip/releases/latest/download/City.mmdb"); err != nil {
		log.Printf("Failed to download new City DB: %v\n", err)
		return
	}
	if err := downloadFile(asnTmp, "https://github.com/xjasonlyu/maxmind-geoip/releases/latest/download/ASN.mmdb"); err != nil {
		log.Printf("Failed to download new ASN DB: %v\n", err)
		return
	}

	// 尝试打开新数据库 验证文件完整性和可用性
	newCityDB, err := maxminddb.Open(cityTmp)
	if err != nil {
		log.Printf("Failed to open newly downloaded City DB: %v\n", err)
		return
	}
	newAsnDB, err := maxminddb.Open(asnTmp)
	if err != nil {
		log.Printf("Failed to open newly downloaded ASN DB: %v\n", err)
		newCityDB.Close()
		return
	}

	// 获取写锁
	databaseMutex.Lock()
	oldCityDB := cityDatabase
	oldAsnDB := asnDatabase
	cityDatabase = newCityDB
	asnDatabase = newAsnDB
	databaseMutex.Unlock()

	// 释放锁安全关闭旧的数据库句柄
	if oldCityDB != nil {
		oldCityDB.Close()
	}
	if oldAsnDB != nil {
		oldAsnDB.Close()
	}

	_ = os.Rename(cityTmp, cityFinal)
	_ = os.Rename(asnTmp, asnFinal)

	log.Println("Database update complete.")
}

// 定时任务调度器
func startCronJob() {
	go func() {
		for {
			now := time.Now().UTC()
			// 计算到下个周日的天数
			daysUntilSunday := int(time.Sunday - now.Weekday())
			if daysUntilSunday < 0 {
				daysUntilSunday += 7
			}

			// 计算下个周日 UTC 0:00:00 的精准时间
			nextSunday := time.Date(now.Year(), now.Month(), now.Day()+daysUntilSunday, 0, 0, 0, 0, time.UTC)

			if nextSunday.Before(now) || nextSunday.Equal(now) {
				nextSunday = nextSunday.AddDate(0, 0, 7)
			}

			sleepDuration := nextSunday.Sub(now)
			log.Printf("Next database update scheduled in %v (at %v UTC)\n", sleepDuration, nextSunday)

			time.Sleep(sleepDuration)

			updateDatabases()
		}
	}()
}

func main() {
	var err error

	// 确保 db 目录存在
	if err := os.MkdirAll(dbDir, 0755); err != nil {
		log.Fatalf("Failed to create database directory: %v", err)
	}

	cityPath := filepath.Join(dbDir, "City.mmdb")
	asnPath := filepath.Join(dbDir, "ASN.mmdb")

	ensureDatabaseExists(cityPath, "https://github.com/xjasonlyu/maxmind-geoip/releases/latest/download/City.mmdb")
	ensureDatabaseExists(asnPath, "https://github.com/xjasonlyu/maxmind-geoip/releases/latest/download/ASN.mmdb")

	// 加载数据库
	cityDatabase, err = maxminddb.Open(cityPath)
	if err != nil {
		log.Fatalf("Error opening City.mmdb: %v", err)
	}
	defer cityDatabase.Close()

	asnDatabase, err = maxminddb.Open(asnPath)
	if err != nil {
		log.Fatalf("Error opening ASN.mmdb: %v", err)
	}
	defer asnDatabase.Close()

	// 启动后台定时更新任务
	startCronJob()

	http.HandleFunc("/", ipHandler)
	log.Println("maxmind query interface is running on port: 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func ipHandler(writer http.ResponseWriter, request *http.Request) {
	// 允许跨域
	writer.Header().Set("Access-Control-Allow-Origin", "*")

	ipString := strings.TrimPrefix(request.URL.Path, "/")

	if ipString == "" {
		writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
		writer.WriteHeader(http.StatusOK)
		_, _ = writer.Write([]byte("ok"))
		return
	}

	if ipString == "favicon.ico" {
		writer.WriteHeader(http.StatusNoContent)
		return
	}

	// 统一 JSON 响应
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")

	// 校验 IP 合法
	ipAddress := net.ParseIP(ipString)
	if ipAddress == nil {
		writer.WriteHeader(http.StatusBadRequest)
		_, _ = writer.Write([]byte(`{"error": "Invalid IP format"}`))
		return
	}

	// 获取并解析 ?lang= 参数 默认英文
	queryLang := strings.ToLower(request.URL.Query().Get("lang"))
	targetLang := "en"
	switch queryLang {
	case "cn", "zh", "zh-cn", "zh_cn":
		targetLang = "zh-CN"
	case "pt", "br", "pt-br", "pt_br":
		targetLang = "pt-BR"
	case "de", "ger":
		targetLang = "de"
	case "es", "spa":
		targetLang = "es"
	case "fr", "fre":
		targetLang = "fr"
	case "ja", "jp", "jpn":
		targetLang = "ja"
	case "ru", "rus":
		targetLang = "ru"
	case "en", "eng":
		targetLang = "en"
	default:
		if queryLang != "" {
			targetLang = queryLang
		}
	}

	// 辅助提取对应语言
	getName := func(names map[string]string) string {
		if name, exists := names[targetLang]; exists && name != "" {
			return name
		}
		return names["en"]
	}

	// 使用共享读锁包围读取操作 保障数据库更新时的内存安全
	databaseMutex.RLock()
	var cityRecord CityRecord
	_ = cityDatabase.Lookup(ipAddress, &cityRecord)

	var asnRecord ASNRecord
	_ = asnDatabase.Lookup(ipAddress, &asnRecord)
	databaseMutex.RUnlock()

	apiResponse := FlatResponse{
		IP: ipAddress.String(),
	}

	// 填充 ASN
	if asnRecord.AutonomousSystemNumber != 0 {
		asnValue := asnRecord.AutonomousSystemNumber
		apiResponse.ASN = &asnValue
		apiResponse.Org = asnRecord.AutonomousSystemOrganization
	}

	// 填充大洲与国家
	if cityRecord.Continent.Code != "" {
		apiResponse.ContinentCode = cityRecord.Continent.Code
		apiResponse.Continent = getName(cityRecord.Continent.Names)
	}
	if cityRecord.Country.IsoCode != "" {
		apiResponse.CountryCode = cityRecord.Country.IsoCode
		apiResponse.Country = getName(cityRecord.Country.Names)
	}
	if cityRecord.RegisteredCountry.IsoCode != "" {
		apiResponse.RegisteredCountryCode = cityRecord.RegisteredCountry.IsoCode
		apiResponse.RegisteredCountry = getName(cityRecord.RegisteredCountry.Names)
	}

	// 填充行政区划
	if len(cityRecord.Subdivisions) > 0 {
		apiResponse.RegionCode = cityRecord.Subdivisions[0].IsoCode
		apiResponse.Region = getName(cityRecord.Subdivisions[0].Names)
	}
	if len(cityRecord.City.Names) > 0 {
		apiResponse.City = getName(cityRecord.City.Names)
	}
	if cityRecord.Postal.Code != "" {
		apiResponse.PostalCode = cityRecord.Postal.Code
	}

	// 填充坐标
	if cityRecord.Location.Latitude != 0 || cityRecord.Location.Longitude != 0 {
		latitude := cityRecord.Location.Latitude
		longitude := cityRecord.Location.Longitude
		apiResponse.Latitude = &latitude
		apiResponse.Longitude = &longitude
	}
	if cityRecord.Location.AccuracyRadius != 0 {
		accuracyRadius := cityRecord.Location.AccuracyRadius
		apiResponse.AccuracyRadius = &accuracyRadius
	}

	// 填充时区和动态计算
	if cityRecord.Location.TimeZone != "" {
		apiResponse.TimeZone = cityRecord.Location.TimeZone
		timeLocation, err := getCachedTimeLocation(cityRecord.Location.TimeZone)
		if err == nil {
			_, timeOffset := time.Now().In(timeLocation).Zone()
			apiResponse.Offset = &timeOffset
		}
	}

	encoder := json.NewEncoder(writer)
	encoder.SetIndent("", "  ")
	_ = encoder.Encode(apiResponse)
}
