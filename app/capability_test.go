package main

import "testing"

func TestParseVulkanICDAPIVersion(t *testing.T) {
	cases := []struct {
		name     string
		manifest string
		want     string
	}{
		{"standard manifest", `{"file_format_version":"1.0.0","ICD":{"library_path":"C:\\gpu.json","api_version":"1.3.280"}}`, "1.3.280"},
		{"unknown fields tolerated", `{"ICD":{"api_version":"1.2.3","library_path":"x"},"other":{"a":1}}`, "1.2.3"},
		{"missing version", `{"ICD":{"library_path":"x"}}`, ""},
		{"missing ICD object", `{"file_format_version":"1.0.0"}`, ""},
		{"malformed json", `{"ICD":`, ""},
		{"empty", "", ""},
		{"whitespace tolerated", `{"ICD":{"api_version":" 1.3.0 "}}`, "1.3.0"},
	}
	for _, c := range cases {
		if got := parseVulkanICDAPIVersion([]byte(c.manifest)); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}

func TestVulkanSupports13(t *testing.T) {
	cases := []struct {
		version string
		want    bool
	}{
		{"1.3.0", true},
		{"1.3.280", true},
		{"1.4.0", true},
		{"2.0.0", true},
		{"1.3", true},
		{"1.2.9", false},
		{"1.2", false},
		{"0.9.2", false},
		{"", false},
		{"bogus", false},
		{"1", false},
		{"1.x.0", false},
		{"-1.3.0", false},
	}
	for _, c := range cases {
		if got := vulkanSupports13(c.version); got != c.want {
			t.Errorf("%q: got %v, want %v", c.version, got, c.want)
		}
	}
}

func TestVulkanProbeDescribe(t *testing.T) {
	cases := []struct {
		name  string
		probe vulkanProbe
		want  string
	}{
		{"registry failure", vulkanProbe{Error: "registry key unreadable"}, "unknown (registry key unreadable)"},
		{"1.3 driver", vulkanProbe{Loader: true, ICDs: []vulkanICD{{Manifest: "a.json", APIVersion: "1.3.280"}}}, "1.3.280 via 1 driver(s)"},
		{"below 1.3", vulkanProbe{ICDs: []vulkanICD{{Manifest: "a.json", APIVersion: "1.2.9"}}}, "1.2.9 via 1 driver(s) (below 1.3)"},
		{"highest wins numerically", vulkanProbe{ICDs: []vulkanICD{{APIVersion: "1.2.3"}, {APIVersion: "1.10.0"}, {APIVersion: "1.9.0"}}}, "1.10.0 via 3 driver(s)"},
		{"unparseable versions skipped", vulkanProbe{ICDs: []vulkanICD{{APIVersion: "bogus"}, {APIVersion: "1.3.0"}}}, "1.3.0 via 2 driver(s)"},
		{"loader without drivers", vulkanProbe{Loader: true}, "loader present, no drivers registered"},
		{"nothing detected", vulkanProbe{}, "not detected"},
	}
	for _, c := range cases {
		if got := c.probe.describe(); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}
