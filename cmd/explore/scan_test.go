package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDuSizeKBOnRealFile(t *testing.T) {
	dir := t.TempDir()
	f := filepath.Join(dir, "payload.bin")
	if err := os.WriteFile(f, make([]byte, 200*1024), 0o644); err != nil {
		t.Fatal(err)
	}
	got := duSizeKB(dir)
	if got <= 0 {
		t.Fatalf("duSizeKB(%q) = %d, want > 0", dir, got)
	}
}

func TestDuSizeKBMissingPath(t *testing.T) {
	if got := duSizeKB("/nonexistent/definitely/not/here"); got != 0 {
		t.Errorf("duSizeKB(missing) = %d, want 0", got)
	}
}

func TestSizeDirsParallel(t *testing.T) {
	a := t.TempDir()
	b := t.TempDir()
	if err := os.WriteFile(filepath.Join(a, "f"), make([]byte, 4096), 0o644); err != nil {
		t.Fatal(err)
	}
	sizes := sizeDirsParallel([]string{a, b})
	if len(sizes) != 2 {
		t.Fatalf("expected 2 results, got %d", len(sizes))
	}
	if sizes[a] <= 0 {
		t.Errorf("expected nonzero size for %q", a)
	}
}

func TestListDirBasic(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "file.txt"), []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}

	entries, err := listDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d: %+v", len(entries), entries)
	}

	byLabel := map[string]entry{}
	for _, e := range entries {
		byLabel[e.label] = e
	}

	sub, ok := byLabel["sub"]
	if !ok || !sub.isDir || sub.sized {
		t.Errorf("dir entry wrong: %+v", sub)
	}
	file, ok := byLabel["file.txt"]
	if !ok || file.isDir || !file.sized || file.bytes != 5 {
		t.Errorf("file entry wrong: %+v", file)
	}
}

func TestListDirMissingPath(t *testing.T) {
	if _, err := listDir("/nonexistent/definitely/not/here"); err == nil {
		t.Error("expected an error for a missing directory")
	}
}

func TestStatDevMissingPath(t *testing.T) {
	if dev := statDev("/nonexistent/definitely/not/here"); dev != 0 {
		t.Errorf("statDev(missing) = %d, want 0", dev)
	}
}
