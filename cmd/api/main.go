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
		/hello:
		- establish an initialization data, data_counter, MAC address etc.
		- server response with hwm, server_time

		/insert

		/metrics (debug)


			happy case (if incoming data_counter is gt last_data_hwm)
				// check if the device exist
				step 1: process batch data
				step 2: insert data points up to the HWM (pgx.Tx  or  CopyFrom), ON CONFLICT DO NOTHING
				step 3: response with: server_time, last_data_hwm

			case 1: (if incoming data_counter is lt last_data_hwm)
				step 1: disregard the incoming data and response with : server_time, and last_data_hwm

			case 2: very first data point, when data_counter = 1 (or 0?)

			case 3: when there's a gap in data_counter (i.e., 1, 2, 4, 5), which indicate hardware issue
				step 1: mark is_broken = true,
				step 2: trace device_id in the event table?
				step 3: response with: server_time, last_data_hwm?

		**/

		w.WriteHeader(http.StatusCreated)
		fmt.Fprintf(w, "Metric recorded successfully for %s", m.Location)
	}
}
