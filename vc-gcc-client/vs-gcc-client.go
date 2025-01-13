package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
)

// CompilationResponse represents the response from the compilation server.
// It contains the compilation status, any error messages, and the compiled binary data.
type CompilationResponse struct {
	Success bool   `json:"success"`          // Indicates if compilation was successful
	Error   string `json:"error,omitempty"`  // Error message if compilation failed
	Binary  []byte `json:"binary,omitempty"` // Compiled binary data if successful
}

func main() {
	if len(os.Args) != 3 {
		log.Fatalf("Usage: %s <input.c> <output.so>", os.Args[0])
	}

	inputFile := os.Args[1]
	outputFile := os.Args[2]

	// Get server URL from environment variable
	serverURL := os.Getenv("VS_GCC_SERVER")
	if serverURL == "" {
		serverURL = "http://localhost:8080"
	}

	// Read the source file
	sourceCode, err := os.ReadFile(inputFile)
	if err != nil {
		log.Fatalf("Failed to read source file: %v", err)
	}

	// Create multipart form data
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	// Add the source file
	part, err := writer.CreateFormFile("source", filepath.Base(inputFile))
	if err != nil {
		log.Fatalf("Failed to create form file: %v", err)
	}
	_, err = part.Write(sourceCode)
	if err != nil {
		log.Fatalf("Failed to write source code to form: %v", err)
	}
	writer.Close()

	// Create HTTP request
	req, err := http.NewRequest("POST", serverURL+"/compile", body)
	if err != nil {
		log.Fatalf("Failed to create request: %v", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	// Send request
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Fatalf("Failed to send request: %v", err)
	}
	defer resp.Body.Close()

	// Read response
	var compResp CompilationResponse
	if err := json.NewDecoder(resp.Body).Decode(&compResp); err != nil {
		log.Fatalf("Failed to decode response: %v", err)
	}

	// Handle compilation error
	if !compResp.Success {
		fmt.Fprintf(os.Stderr, "Compilation failed: %s\n", compResp.Error)
		os.Exit(1)
	}

	// Write binary to output file
	if err := os.WriteFile(outputFile, compResp.Binary, 0o644); err != nil {
		log.Fatalf("Failed to write output file: %v", err)
	}
}
