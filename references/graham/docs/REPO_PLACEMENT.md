# Suggested Repository Placement

## Preferred

Copy the entire pack into the Mildew repository at:

```text
reference/graham/
```

This preserves source/reference materials separately from runtime assets.

## Suggested resulting tree

```text
Mildew/
├── CLAUDE.md
├── docs/
├── reference/
│   └── graham/
│       ├── README.md
│       ├── docs/
│       ├── reference/
│       ├── assets/
│       ├── config/
│       └── godot_example/
└── game/                         # or existing Godot project folder
    └── assets/
        └── graham/               # only runtime-selected copies/imports
```

Do not automatically ship all source/reference MP4/WAV material inside the APK. Reference files belong in the repo, not necessarily the runtime package.
