package main

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func fixtureModel() model {
	m := initialModel([]rootDef{
		{"Home", "/tmp/home"},
		{"Applications", "/tmp/apps"},
		{"Library", "/tmp/lib"},
	})
	m.width, m.height = 80, 24
	return m
}

func TestInitialModelBuildsRootsLevel(t *testing.T) {
	m := fixtureModel()
	if len(m.stack) != 1 {
		t.Fatalf("expected 1 level on stack, got %d", len(m.stack))
	}
	if len(m.stack[0].entries) != 3 {
		t.Fatalf("expected 3 root entries, got %d", len(m.stack[0].entries))
	}
	if !m.stack[0].sizing {
		t.Errorf("expected initial level to start sizing")
	}
}

func TestSizedMsgSortsDescByBytes(t *testing.T) {
	m := fixtureModel()
	updated, _ := m.Update(sizedMsg{sizes: map[string]int64{
		"/tmp/home": 100,
		"/tmp/apps": 300,
		"/tmp/lib":  200,
	}})
	m2 := updated.(model)
	lvl := m2.stack[len(m2.stack)-1]
	if lvl.sizing {
		t.Errorf("expected sizing=false after sizedMsg")
	}
	want := []string{"Applications", "Library", "Home"} // 300, 200, 100
	for i, label := range want {
		if lvl.entries[i].label != label {
			t.Errorf("entries[%d] = %q, want %q (order: %v)", i, lvl.entries[i].label, label, lvl.entries)
		}
	}
}

func TestCursorNavigationClamps(t *testing.T) {
	m := fixtureModel()
	// Up at cursor 0 stays at 0.
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyUp})
	m2 := updated.(model)
	if m2.stack[0].cursor != 0 {
		t.Errorf("cursor went negative: %d", m2.stack[0].cursor)
	}

	// Down twice from 0 with 3 entries -> cursor 2, then Down again stays at 2.
	updated, _ = m2.Update(tea.KeyMsg{Type: tea.KeyDown})
	m3 := updated.(model)
	updated, _ = m3.Update(tea.KeyMsg{Type: tea.KeyDown})
	m4 := updated.(model)
	if m4.stack[0].cursor != 2 {
		t.Fatalf("expected cursor 2, got %d", m4.stack[0].cursor)
	}
	updated, _ = m4.Update(tea.KeyMsg{Type: tea.KeyDown})
	m5 := updated.(model)
	if m5.stack[0].cursor != 2 {
		t.Errorf("cursor overran end: %d", m5.stack[0].cursor)
	}
}

func TestGAndShiftGJumpTopBottom(t *testing.T) {
	m := fixtureModel()
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("G")})
	m2 := updated.(model)
	if m2.stack[0].cursor != 2 {
		t.Fatalf("'G' should jump to last entry, got cursor=%d", m2.stack[0].cursor)
	}
	updated, _ = m2.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("g")})
	m3 := updated.(model)
	if m3.stack[0].cursor != 0 {
		t.Errorf("'g' should jump to first entry, got cursor=%d", m3.stack[0].cursor)
	}
}

func TestQuitKeysSetQuit(t *testing.T) {
	for _, key := range []tea.KeyMsg{
		{Type: tea.KeyRunes, Runes: []rune("q")},
		{Type: tea.KeyEsc},
		{Type: tea.KeyCtrlC},
	} {
		m := fixtureModel()
		updated, cmd := m.Update(key)
		m2 := updated.(model)
		if !m2.quit {
			t.Errorf("key %v did not set quit", key)
		}
		if cmd == nil {
			t.Errorf("key %v did not return tea.Quit cmd", key)
		}
	}
}

func TestLeftAtRootQuits(t *testing.T) {
	m := fixtureModel()
	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyLeft})
	m2 := updated.(model)
	if !m2.quit || cmd == nil {
		t.Errorf("left/back at root level should quit, got quit=%v cmd=%v", m2.quit, cmd)
	}
}

func TestEnterOnDirPushesLevel(t *testing.T) {
	m := fixtureModel()
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("expected a Cmd (listDirCmd) when drilling into a directory")
	}
	// Simulate what handleKey did by re-deriving the model directly, since
	// Update returns tea.Model (interface) and we need the concrete stack.
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	m2 := updated.(model)
	if len(m2.stack) != 2 {
		t.Fatalf("expected stack depth 2 after drilling in, got %d", len(m2.stack))
	}
	if m2.stack[1].path != "/tmp/home" {
		t.Errorf("expected to drill into /tmp/home, got %q", m2.stack[1].path)
	}
}

func TestLeftPopsLevel(t *testing.T) {
	m := fixtureModel()
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	m2 := updated.(model)
	if len(m2.stack) != 2 {
		t.Fatalf("setup: expected stack depth 2, got %d", len(m2.stack))
	}
	updated, cmd := m2.Update(tea.KeyMsg{Type: tea.KeyLeft})
	m3 := updated.(model)
	if len(m3.stack) != 1 {
		t.Errorf("expected left to pop back to depth 1, got %d", len(m3.stack))
	}
	if cmd != nil {
		t.Errorf("popping a level should not schedule a new Cmd")
	}
}
