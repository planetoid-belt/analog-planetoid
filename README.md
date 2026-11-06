# ANALOG PLANETOID
> *A planetoid-terraforming simulator using MIDI instruments as input.*

![](docs/embeds/space-wallpaper.jpg)

## Doc links
- [Godot workflow](docs/godot_workflow.md) - Start here if you are unfamiliar with godot! 
- [procedural generation](docs/procedural_generation.md) - notes & sources for procedural generation. 
- [volume rendering](docs/volume_rendering.md) - notes & sources for volume rendering.

## Directory Structure
- `docs/` is where we store documentation! put markdown files there with notes and stuff. Put any images you want to include in your docs in `docs/embeds/`.
- `assets/` will keep aaaall of the project's assets, which includes `shaders/` and `.tres` files.
- `packedscenes/` contains "prefabs". You can see that boat components are in there for instance. These scenes are meant to be used inside of other scenes, such as constructing a boat, etc..  
- `playscenes/` contains any scene that is meant to be played (differing from `packedscenes/`). 
- `docs/` is where we store documentation :) please keep everything in markdown format and be sure to link to your sources!
- Keep all scripts in `src/` folder.

## Dependencies 
- Godot 4.7.2 
- MIDI plugin 

## Credits
give credits to: 
- VIC studio, 
- authors of papers we implement,
- authors of any plugins or tools we end up using (incl. godot)
