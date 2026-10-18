_:

{
  # Mesa comes from nixpkgs stable. Chaotic stays imported for its vendored
  # Jovian module (Steam Deck), not for mesa-git; re-enable below only for a
  # specific upstream fix, with a Deck rebuild to verify it.
  chaotic.mesa-git.enable = false;
}
