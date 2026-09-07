_: {
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # 50, not 100: a full-RAM zram device lets the allocator push the
    # whole of RAM into compressed swap and thrash. Override per host
    # with more headroom (desktop) if needed.
    memoryPercent = 50;
    priority = 100;
  };
}
