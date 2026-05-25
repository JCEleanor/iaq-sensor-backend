package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	// format: postgres://<user>:<password>@<host>:<port>/<dbname>
	conStr := "postgres://postgres:password@localhost:5433/postgres"

	config, err := pgxpool.ParseConfig(conStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to parse connection string: %v\n", err)
		os.Exit(1)
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to create connection pool: %v\n", err)
		os.Exit(1)
	}

	defer pool.Close()

	http.HandleFunc("/hello", handlePostMetrics(pool))
	// http.HandleFunc("/metrics/search", handleGetMetricsByLocation(pool))
	// http.HandleFunc("/stats", handleGetStats(pool))

	fmt.Println("Server is running on http://localhost:8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
	// err = pool.Ping(context.Background())
	// if err != nil {
	// 	log.Fatalf("Unable to connect to database %v\n", err)

	// }

	// fmt.Println("Successfully connected to TimescaleDB!")
}

func handlePostMetrics(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {

		// only allow POST requests
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Decode the JSON body into our WeatherMetric struct
		var m WeatherMetric
		err := json.NewDecoder(r.Body).Decode(&m)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		/**
			happy case (if existing data_counter is lt m.data_counter)
				step 1: process batch data
				step 2: only insert data points up to the HWM (pgx.Tx  or  CopyFrom), ON CONFLICT DO NOTHING
				step 3: response with: server_time, data_counter

			case 1: (if existing data_counter is gt m.data_counter)
				step 1: disregard the incoming data and response with : server_time, and the existing data_counter

			case 2: when data_counter = 1 (or 0?)

			case 3: when data_counter is not continuous (i.e., 1, 2, 4, 5), which indicate hardware issue

		**/

		w.WriteHeader(http.StatusCreated)
		fmt.Fprintf(w, "Metric recorded successfully for %s", m.Location)
	}
}
