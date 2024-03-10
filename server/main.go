package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"
)

// Структура для хранения информации о загружаемом файле
type FileChunk struct {
	Index int
	Path  string
}

// Map для хранения частей файлов, ключ - имя файла
var files = make(map[string][]*FileChunk)
var mutex = &sync.Mutex{}

func uploadChunkHandler(w http.ResponseWriter, r *http.Request) {
	// Проверка на метод POST
	if r.Method != "POST" {
		http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
		return
	}

	time.Sleep(2 * time.Millisecond)
	err := r.ParseMultipartForm(1024 * 1024 * 5) // 5MB max memory
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	file, handler, err := r.FormFile("file")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer file.Close()

	chunkIndex, err := strconv.Atoi(r.FormValue("index"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Создаем директорию для временных файлов, если ее нет
	tempDir := "temp"
	if _, err := os.Stat(tempDir); os.IsNotExist(err) {
		os.Mkdir(tempDir, 0755)
	}

	// Сохраняем часть файла
	tempFilePath := filepath.Join(tempDir, fmt.Sprintf("%s_part_%d", handler.Filename, chunkIndex))
	tempFile, err := os.Create(tempFilePath)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer tempFile.Close()

	_, err = io.Copy(tempFile, file)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Добавляем информацию о части файла в map
	mutex.Lock()
	files[handler.Filename] = append(files[handler.Filename], &FileChunk{Index: chunkIndex, Path: tempFilePath})
	mutex.Unlock()

	// Отправляем ответ клиенту
	w.WriteHeader(http.StatusOK)
	fmt.Println(w, "Chunk %d uploaded successfully", files)
	fmt.Fprintf(w, "Chunk %d uploaded successfully", chunkIndex)
}

func main() {
	http.HandleFunc("/upload_chunk", uploadChunkHandler)
	fmt.Println("Server started on :8080")
	http.ListenAndServe(":8080", nil)
}
