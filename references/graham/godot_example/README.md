# Godot Example

`graham_presenter.gd` demonstrates the intended architectural contract:

- gameplay/Director requests semantic state IDs;
- renderer resolves missing states through fallbacks;
- assets can later be replaced without changing Director logic;
- still plates receive tiny live-camera motion;
- major emotional transitions should normally be hidden behind broadcast cutaways.

It is not intended to dictate the final Mildew scene tree. Integrate with the actual project architecture.
