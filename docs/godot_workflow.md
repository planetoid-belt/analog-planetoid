# Godot & Git Workflow Guide

This guide covers rules, Git strategies for game engines, and Godot architecture patterns to keep the codebase clean and merge conflict-free.

---

## Git & Scene Rule: The Readers-Writers Problem

If you aren't familiar with the [readers-writers problem](https://en.wikipedia.org/wiki/Readers%E2%80%93writers_problem), it is a classic concurrency challenge: multiple readers can access a resource simultaneously, but only one writer can access a resource at a time, and during that time, no reading of the hogged resource is allowed.

Game engine scenes (`.tscn` files, especially inside `packedscenes` and `playscenes`) behave like exclusive resources because they cannot be easily merged with Git.

> [!IMPORTANT]
> **Never work on the same scene file as someone else at the same time, regardless of what branch you are on.**
> * Develop features in **dedicated, isolated scenes**.
> * Make copies of resources if you need to test functionality locally.


### Handling `main_scene.tscn`

> [!IMPORTANT]
> **Nobody has ownership of `main_scene.tscn`.** Avoid making direct edits to it to prevent catastrophic merge conflicts.
> * Keep `main_scene.tscn` strictly for final integration.
> * Features should only be merged into it once they are fully stable.
> * Any updates or integrations into `main_scene.tscn` require explicit coordination and a green light from the team (-gepete).
 


---

## Godot Architecture & Core Concepts

[Introduction to Godot Official Documentation](https://docs.godotengine.org/en/stable/getting_started/introduction/index.html)

Godot is a node-based game engine where everything is organized as a tree of nodes. Nodes handle everything from audio players and mesh instances, to hitboxes, particle systems, and script holding.

There are three foundational node classes: `Node3D`, `Node2D`, and `Node`. The base `Node` is a parent to the rest and is extremely lightweight because it does not store positional data—making it ideal for holding utility scripts.

> [!TIP]
> Since this is a **3D project**, you should rarely ever need to create `Node2D` nodes. 

Godot uses its own scripting language called GDScript, which is ergonomically integrated into the editor. [GDScript Reference Documentation](https://docs.godotengine.org/en/latest/tutorials/scripting/gdscript/gdscript_basics.html)

### Architecture Rule: Propagate Down, Signal Up

> *"Propagate down, signal up."*

* **Propagate Down:** If a parent node needs to update or trigger behavior on a node further down the tree, call down through its references or path.
* **Signal Up:** Nested nodes should never directly reference or tightly couple to their parents. Instead, send updates upward using **[signals](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html)**—Godot's built-in implementation of the [Observer Pattern](https://en.wikipedia.org/wiki/Observer_pattern).
* *Tip:* Use the Godot Editor UI to connect signals; it provides an incredible visual overview of which nodes are listening to what.



### Leverage `@export` Blocks

In GDScript, `@export` is a powerful keyword that exposes variables directly in the Godot Editor UI.

* Avoid hardcoding magic numbers deep inside scripts.
* Taking the extra time to write clean `@export` variables makes tuning gameplay collaborative and accessible for everyone on the team without needing to edit the code. 
* [Godot Exports Documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_exports.html)

---

## Naming Conventions Reference
Adhere strictly to the following naming conventions:

| Type | Convention | Example |
| --- | --- | --- |
| **File names** | `snake_case` | `yaml_parser.gd` |
| **Class names** | `PascalCase` | `class_name YAMLParser` |
| **Node names** | `PascalCase` | `Camera3D`, `Player` |
| **Functions** | `snake_case` | `func load_level():` |
| **Variables** | `snake_case` | `var particle_effect` |
| **Signals** | `snake_case` | `signal door_opened` |
| **Constants** | `CONSTANT_CASE` | `const MAX_SPEED = 200` |
| **Enum names** | `PascalCase` | `enum Element` |
| **Enum members** | `CONSTANT_CASE` | `{EARTH, WATER, AIR, FIRE}` |
