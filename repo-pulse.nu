#!/usr/bin/env nu
# repo-pulse.nu — one-shot repo dashboard: commit cadence, biggest Nix files, stalest flake pins.
# Run from the flake root so `git ls-files` and `flake.lock` resolve: `nu repo-pulse.nu`.

def bar [n, mx, w] {
  let raw = (($n / $mx) * $w | math round | into int)
  let k = (if $raw < 1 { 1 } else { $raw })
  0..<$k | each { '█' } | str join
}
def tick [n, mx] {
  let chars = ('▁▂▃▄▅▆▇█' | split chars)
  let last = (($chars | length) - 1)
  let idx = (($n / $mx) * $last | math round | into int)
  $chars | get $idx
}

# 1 · commit heartbeat
let by_day = (^git log --pretty=format:'%ad' --date=format:'%Y-%m-%d' -n 3000
  | lines | wrap date | histogram date)
let days = (0..41 | each {|i|
  let d = ((date now) - ($i * 1day) | format date '%Y-%m-%d')
  {date: $d, n: ($by_day | where date == $d | get count.0? | default 0)}
} | reverse)
let sig = ($days | get n | math max)
let spark = ($days | each {|r| tick $r.n $sig } | str join)

# 2 · heaviest .nix files, line-counted in parallel
let big = (^git ls-files '*.nix' | lines | par-each {|f|
  {file: $f, loc: (open --raw $f | lines | where {|l| ($l | str trim) != ''} | length)}
} | sort-by loc --reverse | first 10)
let bmx = ($big | get loc | math max)
let big_table = ($big | each {|r| {file: $r.file, loc: $r.loc, profile: (bar $r.loc $bmx 30)}} | table -i false)

# 3 · top-level flake pins, epoch seconds -> age in days
let lock = (open --raw flake.lock | from json)
let pins = ($lock.nodes.root.inputs | transpose input ref | each {|r|
  let n = ($lock.nodes | get $r.ref)
  {input: $r.input, days: ((((date now) - ($n.locked.lastModified * 1_000_000_000 | into datetime)) / 1day) | math floor | into int)}
} | sort-by days --reverse | first 10)
let pmx = ($pins | get days | math max)
let pin_table = ($pins | each {|r| {input: $r.input, days: $r.days, profile: (bar $r.days $pmx 30)}} | table -i false)

[
  $"REPO PULSE · ($env.PWD)"
  ""
  $"COMMITS PER DAY · ($days | get date | first) → ($days | get date | last) · peak ($sig) · total ($days | get n | math sum)"
  $spark
  ""
  "HEAVIEST NIX FILES · non-blank lines"
  $big_table
  ""
  "TOP-LEVEL FLAKE PINS · days since locked revision"
  $pin_table
] | str join "\n"
