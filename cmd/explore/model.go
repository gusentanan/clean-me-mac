package main

import (
	"os/exec"
	"sort"

	tea "github.com/charmbracelet/bubbletea"
)

// entry is one row: a directory or file inside the current level.
type entry struct {
	label string
	path  string
	isDir bool
	bytes int64
	sized bool
}

// rootDef is one named starting point (Home, Applications, ...), passed in
// from bash via --roots so the definitions stay single-sourced in
// lib/explore.sh's _explore_root_defs rather than duplicated here.
type rootDef struct {
	label string
	path  string
}

// level is one screen in the drill-down stack: a breadcrumb, the entries
// at that path (roots screen has path == ""), and independent cursor/
// scroll state so popping back to a parent level restores where the user
// was.
type level struct {
	breadcrumb string
	path       string
	entries    []entry
	cursor     int
	sizing     bool
}

type model struct {
	stack  []level
	width  int
	height int
	quit   bool
	err    error
}

type levelReadyMsg struct {
	entries []entry
	err     error
}

type sizedMsg struct {
	sizes map[string]int64
}

func initialModel(roots []rootDef) model {
	entries := make([]entry, 0, len(roots))
	for _, r := range roots {
		entries = append(entries, entry{label: r.label, path: r.path, isDir: true})
	}
	return model{
		stack: []level{{breadcrumb: "clmac explore", entries: entries, sizing: len(entries) > 0}},
	}
}

func (m model) Init() tea.Cmd {
	return sizeCurrentLevelCmd(m.stack[len(m.stack)-1])
}

// sizeCurrentLevelCmd sizes every directory entry in a level in parallel.
// Files are already sized in listDir/initialModel and skipped here.
func sizeCurrentLevelCmd(lvl level) tea.Cmd {
	var dirPaths []string
	for _, e := range lvl.entries {
		if e.isDir && !e.sized {
			dirPaths = append(dirPaths, e.path)
		}
	}
	if len(dirPaths) == 0 {
		return nil
	}
	return func() tea.Msg {
		return sizedMsg{sizes: sizeDirsParallel(dirPaths)}
	}
}

func listDirCmd(path string) tea.Cmd {
	return func() tea.Msg {
		entries, err := listDir(path)
		return levelReadyMsg{entries: entries, err: err}
	}
}

func revealInFinder(path string) tea.Cmd {
	return func() tea.Msg {
		_ = exec.Command("open", "-R", path).Start()
		return nil
	}
}

func (m model) cur() *level {
	return &m.stack[len(m.stack)-1]
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil

	case levelReadyMsg:
		lvl := m.cur()
		if msg.err != nil {
			m.err = msg.err
			return m, nil
		}
		lvl.entries = msg.entries
		lvl.sizing = true
		return m, sizeCurrentLevelCmd(*lvl)

	case sizedMsg:
		lvl := m.cur()
		for i := range lvl.entries {
			if sz, ok := msg.sizes[lvl.entries[i].path]; ok {
				lvl.entries[i].bytes = sz
				lvl.entries[i].sized = true
			}
		}
		sort.SliceStable(lvl.entries, func(i, j int) bool {
			return lvl.entries[i].bytes > lvl.entries[j].bytes
		})
		lvl.sizing = false
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	lvl := m.cur()
	n := len(lvl.entries)

	switch msg.String() {
	case "q", "esc", "ctrl+c":
		m.quit = true
		return m, tea.Quit

	case "up", "k":
		if lvl.cursor > 0 {
			lvl.cursor--
		}
	case "down", "j":
		if lvl.cursor < n-1 {
			lvl.cursor++
		}
	case "g":
		lvl.cursor = 0
	case "G":
		if n > 0 {
			lvl.cursor = n - 1
		}

	case "left", "h", "backspace":
		if len(m.stack) > 1 {
			m.stack = m.stack[:len(m.stack)-1]
		} else {
			m.quit = true
			return m, tea.Quit
		}

	case "enter", "right", "l":
		if n == 0 {
			return m, nil
		}
		chosen := lvl.entries[lvl.cursor]
		if chosen.isDir {
			m.stack = append(m.stack, level{
				breadcrumb: chosen.path,
				path:       chosen.path,
				sizing:     true,
			})
			return m, listDirCmd(chosen.path)
		}
		return m, revealInFinder(chosen.path)
	}
	return m, nil
}
