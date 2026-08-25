package main

import (
	"context"
	"encoding/json"
	"os"
	"time"

	"github.com/sagernet/sing-box/experimental/v2rayapi"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	address := "127.0.0.1:8080"
	if len(os.Args) > 1 { address = os.Args[1] }
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	connection, err := grpc.DialContext(ctx, address, grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithBlock())
	if err != nil { panic(err) }
	defer connection.Close()
	request := &v2rayapi.QueryStatsRequest{Patterns: []string{"user>>>"}, Reset_: true}
	response := new(v2rayapi.QueryStatsResponse)
	err = connection.Invoke(ctx, "/v2ray.core.app.stats.command.StatsService/QueryStats", request, response)
	if err != nil { panic(err) }
	result := make(map[string]int64, len(response.Stat))
	for _, stat := range response.Stat { result[stat.Name] = stat.Value }
	if err = json.NewEncoder(os.Stdout).Encode(result); err != nil { panic(err) }
}
