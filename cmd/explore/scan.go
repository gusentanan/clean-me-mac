package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

// duSizeKB runs `du -sk <path>` and converts KB to bytes — same command and
// conversion as lib/common.sh's dir_size, so numbers here stay consistent
// with `clmac scan`/`doctor` instead of diverging from a native tree-walk.
func duSizeKB(path string) int64 {
	out, err := exec.Command("du", "-sk", path).Output()
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		return 0
	}
	kb, err := strconv.ParseInt(fields[0], 10, 64)
	if err != nil {
		return 0
	}
	return kb * 1024
}

// sizeDirsParallel sizes a set of directories with a bounded worker pool —
// same job-count cap (12) as lib/common.sh's dir_size_parallel.
func sizeDirsParallel(paths []string) map[string]int64 {
	jobs := runtime.NumCPU()
	if jobs > 12 {
		jobs = 12
	}
	if jobs < 1 {
		jobs = 1
	}
	results := make(map[string]int64, len(paths))
	var mu sync.Mutex
	sem := make(chan struct{}, jobs)
	var wg sync.WaitGroup
	for _, p := range paths {
		wg.Add(1)
		sem <- struct{}{}
		go func(p string) {
			defer wg.Done()
			defer func() { <-sem }()
			sz := duSizeKB(p)
			mu.Lock()
			results[p] = sz
			mu.Unlock()
		}(p)
	}
	wg.Wait()
	return results
}

// statDev returns the device id for a path, or 0 if it can't be stat'd.
func statDev(path string) uint64 {
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return 0
	}
	return uint64(st.Dev)
}

// listDir lists one directory level. Mirrors explore.sh's
// _explore_dir_screen: files get their size from stat immediately
// (cheap), directories are returned with bytes=0 and sized separately
// (sizeDirsParallel) since du is the expensive part. For /Volumes
// specifically, entries sharing the boot volume's device id are skipped —
// /Volumes commonly lists the boot volume under its own name, already
// covered by Home.
func listDir(path string) ([]entry, error) {
	des, err := os.ReadDir(path)
	if err != nil {
		return nil, err
	}

	isVolumes := filepath.Clean(path) == "/Volumes"
	var rootDev uint64
	if isVolumes {
		rootDev = statDev("/")
	}

	entries := make([]entry, 0, len(des))
	for _, de := range des {
		full := filepath.Join(path, de.Name())
		if isVolumes && rootDev != 0 && statDev(full) == rootDev {
			continue
		}

		isDir := de.IsDir() && de.Type()&os.ModeSymlink == 0
		var fsize int64
		if !isDir {
			if info, err := de.Info(); err == nil {
				fsize = info.Size()
			}
		}
		entries = append(entries, entry{
			label: de.Name(),
			path:  full,
			isDir: isDir,
			bytes: fsize,
			sized: !isDir, // files are already sized; dirs need du
		})
	}
	return entries, nil
}
