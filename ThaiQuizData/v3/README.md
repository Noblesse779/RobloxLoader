# Thai Quiz vocabulary, version 3

Derived from **VOLUBILIS Mundo v25.3 (November 2025)** by **Belisan**.
Original project: https://belisan-volubilis.blogspot.com/
Input mirror: https://github.com/windwerfer/volubilis_dict/blob/main/data/vol_mundo_01.11.2025.xlsx

## License

All vocabulary shards and this derived vocabulary dataset are licensed under
**Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**:
https://creativecommons.org/licenses/by-sa/4.0/

The original author identifies this license at the original project website.
Keep this attribution and share adapted vocabulary data under the same license.

## Changes and format

Thai headwords were extracted, normalized to NFC, whitespace-trimmed and deduplicated.
Rows without a Thai consonant were excluded. English glosses, part-of-speech labels
and domain labels were used to infer game categories; these mappings are approximate.
There are **102,783 unique Thai headwords and phrases**, of which **39,039**
have one or more inferred categories before game-specific length/character filtering.

This is a dictionary, **not 102,783 confirmed game answers**.
The game ultimately determines answer validity.

Each UTF-8 TSV row contains:
`headword<TAB>comma-separated category IDs`.
A row with an empty category field belongs to the general vocabulary only and is
not automatically sent as an answer. The loader checks categorized candidates
with the game's existing checkAnswer interface. It does not submit the full corpus.

UI library: WindUI by Footagesus (MIT), https://github.com/Footagesus/WindUI
A small native fallback window is included if the UI library cannot initialize.
