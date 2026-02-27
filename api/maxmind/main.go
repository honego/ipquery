package main

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
	"strings"
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
	// 基础网络信息
	IP  string `json:"ip"`
	ASN *uint  `json:"asn,omitempty"`
	Org string `json:"org,omitempty"`

	// 大洲与国家信息
	ContinentCode         string `json:"continent_code,omitempty"`
	Continent             string `json:"continent,omitempty"`
	CountryCode           string `json:"country_code,omitempty"`
	Country               string `json:"country,omitempty"`
	RegisteredCountryCode string `json:"registered_country_code,omitempty"`
	RegisteredCountry     string `json:"registered_country,omitempty"`

	// 省市行政区划
	RegionCode string `json:"region_code,omitempty"`
	Region     string `json:"region,omitempty"`
	City       string `json:"city,omitempty"`
	PostalCode string `json:"postal_code,omitempty"`

	// 坐标与精度
	Longitude      *float64 `json:"longitude,omitempty"`
	Latitude       *float64 `json:"latitude,omitempty"`
	AccuracyRadius *uint16  `json:"accuracy_radius,omitempty"`

	// 时区信息
	Offset   *int   `json:"offset,omitempty"`
	TimeZone string `json:"time_zone,omitempty"`
}

var (
	cityDB *maxminddb.Reader
	asnDB  *maxminddb.Reader
)

func main() {
	var err error
	cityDB, err = maxminddb.Open("./City.mmdb")
	if err != nil {
		log.Fatalf("Error opening City.mmdb: %v", err)
	}
	defer cityDB.Close()

	asnDB, err = maxminddb.Open("./ASN.mmdb")
	if err != nil {
		log.Fatalf("Error opening ASN.mmdb: %v", err)
	}
	defer asnDB.Close()

	http.HandleFunc("/", ipHandler)
	log.Println("maxmind query interface is running on port: 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func ipHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	ipStr := strings.TrimPrefix(r.URL.Path, "/")
	if ipStr == "" || ipStr == "favicon.ico" {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error": "Please provide an IP address"}`))
		return
	}

	ip := net.ParseIP(ipStr)
	if ip == nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error": "Invalid IP format"}`))
		return
	}

	var cityRecord CityRecord
	_ = cityDB.Lookup(ip, &cityRecord)

	var asnRecord ASNRecord
	_ = asnDB.Lookup(ip, &asnRecord)

	res := FlatResponse{
		IP: ip.String(),
	}

	// 填充 ASN
	if asnRecord.AutonomousSystemNumber != 0 {
		asn := asnRecord.AutonomousSystemNumber
		res.ASN = &asn
		res.Org = asnRecord.AutonomousSystemOrganization
	}

	// 填充大洲与国家
	if cityRecord.Continent.Code != "" {
		res.ContinentCode = cityRecord.Continent.Code
		res.Continent = cityRecord.Continent.Names["en"]
	}
	if cityRecord.Country.IsoCode != "" {
		res.CountryCode = cityRecord.Country.IsoCode
		res.Country = cityRecord.Country.Names["en"]
	}
	if cityRecord.RegisteredCountry.IsoCode != "" {
		res.RegisteredCountryCode = cityRecord.RegisteredCountry.IsoCode
		res.RegisteredCountry = cityRecord.RegisteredCountry.Names["en"]
	}

	// 填充行政区划
	if len(cityRecord.Subdivisions) > 0 {
		res.RegionCode = cityRecord.Subdivisions[0].IsoCode
		res.Region = cityRecord.Subdivisions[0].Names["en"]
	}
	if cityRecord.City.Names["en"] != "" {
		res.City = cityRecord.City.Names["en"]
	}
	if cityRecord.Postal.Code != "" {
		res.PostalCode = cityRecord.Postal.Code
	}

	// 填充坐标
	if cityRecord.Location.Latitude != 0 || cityRecord.Location.Longitude != 0 {
		lat := cityRecord.Location.Latitude
		lon := cityRecord.Location.Longitude
		res.Latitude = &lat
		res.Longitude = &lon
	}
	if cityRecord.Location.AccuracyRadius != 0 {
		ar := cityRecord.Location.AccuracyRadius
		res.AccuracyRadius = &ar
	}

	// 填充时区和动态计算 Offset
	if cityRecord.Location.TimeZone != "" {
		res.TimeZone = cityRecord.Location.TimeZone
		loc, err := time.LoadLocation(cityRecord.Location.TimeZone)
		if err == nil {
			_, offset := time.Now().In(loc).Zone()
			res.Offset = &offset
		}
	}

	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	_ = encoder.Encode(res)
}
