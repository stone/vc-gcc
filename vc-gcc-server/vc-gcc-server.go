package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
)

type CompilationResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
	Binary  []byte `json:"binary,omitempty"`
}

func main() {
	// Get configuration from environment variables
	port := os.Getenv("VS_GCC_PORT")
	if port == "" {
		port = "8080"
	}

	// Check if gcc is available
	if _, err := exec.LookPath("gcc"); err != nil {
		log.Fatalf("gcc not found in PATH: %v", err)
	}

	http.HandleFunc("/compile", handleCompilation())
	log.Printf("Starting server on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func handleCompilation() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s - \"%s %s %s\" \"%s\"", r.RemoteAddr, r.Method, r.URL.Path, r.Proto, r.UserAgent())
		if r.Method != "POST" {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Parse multipart form
		err := r.ParseMultipartForm(10 << 20) // 10 MB max
		if err != nil {
			sendError(w, fmt.Sprintf("Failed to parse form: %v", err))
			return
		}

		// Get uploaded file
		file, header, err := r.FormFile("source")
		if err != nil {
			sendError(w, fmt.Sprintf("Failed to get source file: %v", err))
			return
		}
		defer file.Close()

		// Create temporary directory
		tmpDir, err := os.MkdirTemp("", "vs-gcc-*")
		if err != nil {
			sendError(w, fmt.Sprintf("Failed to create temp dir: %v", err))
			return
		}
		defer os.RemoveAll(tmpDir)

		// Save source file
		sourcePath := filepath.Join(tmpDir, header.Filename)
		outputPath := filepath.Join(tmpDir, "output.so")

		dst, err := os.Create(sourcePath)
		if err != nil {
			sendError(w, fmt.Sprintf("Failed to create source file: %v", err))
			return
		}
		if _, err := io.Copy(dst, file); err != nil {
			sendError(w, fmt.Sprintf("Failed to save source file: %v", err))
			return
		}
		dst.Close()

		// Prepare gcc command
		cmd := exec.Command("gcc",
			"-g",
			"-O2",
			"-ffile-prefix-map="+tmpDir+"=.",
			"-fstack-protector-strong",
			"-Wformat",
			"-Werror=format-security",
			"-Wall",
			"-Werror",
			"-Wno-error=unused-result",
			"-pthread",
			"-fpic",
			"-shared",
			"-Wl,-x",
			"-o", outputPath,
			sourcePath,
		)

		// Capture stderr for error messages
		var stderr bytes.Buffer
		cmd.Stderr = &stderr

		log.Printf("Compiling %s", sourcePath)

		// Run compilation
		if err := cmd.Run(); err != nil {
			sendError(w, stderr.String())
			return
		}

		// Read compiled binary
		binary, err := os.ReadFile(outputPath)
		if err != nil {
			sendError(w, fmt.Sprintf("Failed to read compiled binary: %v", err))
			return
		}

		log.Printf("Compilation successful")

		// Send response
		response := CompilationResponse{
			Success: true,
			Binary:  binary,
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	}
}

func sendError(w http.ResponseWriter, errMsg string) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(CompilationResponse{
		Success: false,
		Error:   errMsg,
	})
}
