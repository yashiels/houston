#!/usr/bin/env bash
# parse-profile.sh — Parse a TOML profile file and output JSON to stdout.
# Uses only bash/grep/awk. No external TOML parser required.
# Source this file and call: parse_profile <path-to-toml>

set -euo pipefail

parse_profile() {
  local file="${1:?Usage: parse_profile <file.toml>}"

  if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file" >&2
    return 1
  fi

  awk '
  BEGIN {
    section = ""
    section_count = 0
  }

  # Skip comments and blank lines
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }

  # Section header: [foo] or [foo.bar]
  /^[[:space:]]*\[/ {
    s = $0
    gsub(/^[[:space:]]*\[/, "", s)
    gsub(/\][[:space:]]*$/, "", s)
    gsub(/[[:space:]]/, "", s)
    section = s
    next
  }

  # Key = value line
  /=/ {
    line = $0
    eq_pos = index(line, "=")
    if (eq_pos == 0) next

    key = substr(line, 1, eq_pos - 1)
    val = substr(line, eq_pos + 1)

    # Trim whitespace
    gsub(/^[[:space:]]+/, "", key)
    gsub(/[[:space:]]+$/, "", key)
    gsub(/^[[:space:]]+/, "", val)
    gsub(/[[:space:]]+$/, "", val)

    # Remove surrounding quotes from key (reviewer patterns)
    if (match(key, /^".*"$/)) {
      key = substr(key, 2, length(key) - 2)
    }

    # Strip inline comments for non-string, non-array values
    if (!match(val, /^"[^"]*"/) && !match(val, /^\[.*\]/)) {
      gsub(/[[:space:]]+#.*$/, "", val)
    }

    # Store
    idx = section_count++
    sections[idx] = section
    keys[idx] = key
    values[idx] = val
  }

  END {
    printf "{"

    split("profile,identity,linear,platforms,owners,reviewers,detect", top_sections, ",")

    first_top = 1

    for (ts = 1; ts <= 7; ts++) {
      top = top_sections[ts]

      # Check if this top-level section has any data
      has_data = 0
      for (i = 0; i < section_count; i++) {
        if (sections[i] == top || index(sections[i], top ".") == 1) {
          has_data = 1
          break
        }
      }
      if (!has_data) continue

      if (!first_top) printf ","
      first_top = 0

      printf "\"%s\":", top

      # Check for sub-sections
      has_subsec = 0
      for (i = 0; i < section_count; i++) {
        if (index(sections[i], top ".") == 1) {
          has_subsec = 1
          break
        }
      }

      if (has_subsec) {
        printf "{"
        first_child = 1

        # Collect unique sub-section names in order
        delete seen_subsec
        subsec_count = 0
        for (i = 0; i < section_count; i++) {
          if (index(sections[i], top ".") == 1) {
            subsec_name = substr(sections[i], length(top) + 2)
            if (!(subsec_name in seen_subsec)) {
              seen_subsec[subsec_name] = 1
              subsec_order[++subsec_count] = subsec_name
            }
          }
        }

        for (si = 1; si <= subsec_count; si++) {
          cur_subsec = subsec_order[si]
          full_section = top "." cur_subsec

          if (!first_child) printf ","
          first_child = 0

          printf "\"%s\":{", cur_subsec

          first_key = 1
          for (i = 0; i < section_count; i++) {
            if (sections[i] == full_section) {
              if (!first_key) printf ","
              first_key = 0
              print_kv(keys[i], values[i])
            }
          }
          printf "}"
        }

        # Direct keys under the top section itself
        for (i = 0; i < section_count; i++) {
          if (sections[i] == top) {
            if (!first_child) printf ","
            first_child = 0
            print_kv(keys[i], values[i])
          }
        }

        printf "}"
      } else {
        # Simple section
        printf "{"
        first_key = 1
        for (i = 0; i < section_count; i++) {
          if (sections[i] == top) {
            if (!first_key) printf ","
            first_key = 0
            print_kv(keys[i], values[i])
          }
        }
        printf "}"
      }
    }

    printf "}\n"
  }

  function print_kv(k, v,    arr_content, nn, parts, j, inner_val) {
    printf "\"%s\":", escape_json(k)

    if (match(v, /^\[.*\]$/)) {
      arr_content = substr(v, 2, length(v) - 2)
      gsub(/^[[:space:]]+/, "", arr_content)
      gsub(/[[:space:]]+$/, "", arr_content)

      if (arr_content == "") {
        printf "[]"
      } else {
        printf "["
        nn = split_csv(arr_content, parts)
        for (j = 1; j <= nn; j++) {
          if (j > 1) printf ","
          gsub(/^[[:space:]]+/, "", parts[j])
          gsub(/[[:space:]]+$/, "", parts[j])
          if (match(parts[j], /^".*"$/)) {
            inner_val = substr(parts[j], 2, length(parts[j]) - 2)
            printf "\"%s\"", escape_json(inner_val)
          } else {
            printf "%s", parts[j]
          }
        }
        printf "]"
      }
    } else if (match(v, /^".*"$/)) {
      inner_val = substr(v, 2, length(v) - 2)
      printf "\"%s\"", escape_json(inner_val)
    } else if (match(v, /^[0-9]+$/)) {
      printf "%s", v
    } else if (v == "true" || v == "false") {
      printf "%s", v
    } else {
      printf "\"%s\"", escape_json(v)
    }
  }

  function escape_json(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, "\\t", s)
    gsub(/\r/, "\\r", s)
    gsub(/\n/, "\\n", s)
    return s
  }

  function split_csv(str, arr,    ch, ci, in_q, cur, nn) {
    nn = 0
    cur = ""
    in_q = 0
    for (ci = 1; ci <= length(str); ci++) {
      ch = substr(str, ci, 1)
      if (ch == "\"") {
        in_q = !in_q
        cur = cur ch
      } else if (ch == "," && !in_q) {
        arr[++nn] = cur
        cur = ""
      } else {
        cur = cur ch
      }
    }
    if (cur != "") {
      arr[++nn] = cur
    }
    return nn
  }
  ' "$file"
}
