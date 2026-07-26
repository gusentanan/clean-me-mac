package main

import (
	"fmt"
	"strings"
)

const barWidth = 24

// humanSize matches lib/common.sh's human_size formatting (B/K/M/G/T/P,
// one decimal place past the first unit) so numbers read the same as the
// rest of clmac.
func humanSize(bytes int64) string {
	units := []string{"B", "K", "M", "G", "T", "P"}
	b := float64(bytes)
	i := 0
	for b >= 1024 && i < len(units)-1 {
		b /= 1024
		i++
	}
	if i == 0 {
		return fmt.Sprintf("%d%s", int64(b), units[i])
	}
	return fmt.Sprintf("%.1f%s", b, units[i])
}

func bar(bytes, total int64, width int) string {
	filled := 0
	if total > 0 {
		filled = int(float64(bytes) / float64(total) * float64(width))
	}
	if filled > width {
		filled = width
	}
	if filled < 0 {
		filled = 0
	}
	return strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
}

func pct(bytes, total int64) float64 {
	if total <= 0 {
		return 0
	}
	return float64(bytes) / float64(total) * 100
}

func (m model) View() string {
	if m.quit {
		return ""
	}
	if m.err != nil {
		return fmt.Sprintf("\n  clmac explore: %v\n\n  Press q to quit.\n", m.err)
	}

	lvl := m.stack[len(m.stack)-1]
	n := len(lvl.entries)

	var b strings.Builder
	fmt.Fprintf(&b, "\n  \x1b[1mclmac explore\x1b[0m  %s\n", lvl.breadcrumb)
	if lvl.sizing {
		fmt.Fprintf(&b, "  \x1b[2mSizing…\x1b[0m\n\n")
	} else {
		b.WriteString("\n")
	}

	var total int64
	for _, e := range lvl.entries {
		total += e.bytes
	}

	height := m.height
	if height <= 0 {
		height = 24
	}
	visible := height - 8
	if visible < 1 {
		visible = 1
	}
	if visible > n {
		visible = n
	}

	top := 0
	if n > visible {
		top = lvl.cursor - visible/2
		if top < 0 {
			top = 0
		}
		if top > n-visible {
			top = n - visible
		}
	}

	for i := top; i < top+visible && i < n; i++ {
		e := lvl.entries[i]
		pointer := " "
		if i == lvl.cursor {
			pointer = "\x1b[36m\x1b[1m▶\x1b[0m"
		}
		sizeStr := "pending…"
		if e.sized || !e.isDir {
			sizeStr = humanSize(e.bytes)
		}
		fmt.Fprintf(&b, " %s %2d. %s  %5.1f%%  |  %-28s %10s\n",
			pointer, i+1, bar(e.bytes, total, barWidth), pct(e.bytes, total),
			truncate(e.label, 28), sizeStr)
	}

	b.WriteString("\n  \x1b[2m↑↓ Navigate | Enter/→ Open | ← Back | Esc/Q Quit\x1b[0m\n")
	return b.String()
}

func truncate(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	if max <= 3 {
		return string(r[:max])
	}
	return string(r[:max-3]) + "..."
}
