# Gently Down The Stream

## Group 6 - StrathHack 2026

- Name: Callum Penney
- Name: Erin Singleton

## Game Overview

Gently Down The Stream is a cooperative multiplayer river game. Each player controls one oar on the same boat, so the team must communicate and coordinate its rowing to travel down the river, avoid obstacles, and keep the boat afloat.

## How to Play

1. Host a game or join the host using the displayed LAN IP address.
2. Choose an available oar position.
3. Row together using the assigned rowing input.
4. Steer around rocks, logs, and the riverbanks.
5. Travel as far as possible without sinking.

## Features

- Cooperative six-player boat control
- Server authoritative multiplayer movement
- Individual oar positions with different turning effects
- River obstacles, collisions, damage, and game over states
- Procedural terrain and environmental decoration
- Customisable player characters
- Water effects, lighting, and a starting banner

## Tools and Technologies

- Game engine: Godot 4
- Programming language: GDScript
- Networking: Godot High-Level Multiplayer API with ENet
- Assets: KayKit/GameWorld assets, boat assets, and custom environment resources
- Version control: Git and GitHub

## Main Systems

### Player Movement

Each player controls one oar. A rowing stroke applies forward force to the boat and adds turning force based on which side of the boat the oar is on. Opposing oars can balance the turning force and create stronger forward movement.

### Multiplayer

The host acts as the server authority. Players send rowing input to the host, while the host calculates movement, collisions, damage, and the boat's position. The updated boat state and gameplay events are synchronized across connected players.


### Environment

The river, water, flat grassbanks, obstacles, trees, bushes, rocks, and starting banner are created or placed when the river scene loads. Decorations use the same ground height as the terrain so they remain aligned with the ground.

### Damage and Game Over

Colliding with rocks, logs, or riverbanks reduces the boat's hull health. Damage causes a screen flash, camera shake, and notification. The host synchronizes the damage event so every player sees the same result. When hull health reaches zero, all players see the boat-sunk screen together.

## What Went Well

- We created a playable multiplayer prototype within the hackathon timeframe.
- The shared boat gave every player a clear role.
- The game encouraged communication naturally.
- We built a complete loop from lobby to gameplay, damage, game over, and retry.
- We adapted the environment with lighting, water, assets, terrain, and a banner.

## What Could Have Gone Better

- Multiplayer testing should have started earlier.
- Character customisation introduced connection and synchronization issues.
- Imported assets initially had incorrect pivots and appeared to float.
- Runtime-generated content was difficult to preview in the editor.
- We could have defined a smaller minimum viable product earlier.

## Future Expansions
- Add different views for the player in gamplay such as first person and zoom options
- Add more river environments, weather conditions, and visual themes.
- Add rapids, waterfalls, whirlpools, and moving hazards.
- Add more character animations, emotes, and customisation options.
- Add online relay support so players do not need LAN setup.
- Add team records, leaderboards, achievements, and more game modes.
- Add money system for boat upgrades, customization, player upgrades.

## How to Run the Game

1. Open the `gently-down-the-stream` folder in Godot 4.
2. Run the project with `F6` for the current scene or `F5` for the full project.
3. To test multiplayer, host one instance and join from another computer using the host's LAN IP address.


## Credits

- StrathHack 2026
- Godot Engine
- KayKit and GameWorld asset packs
- Boat and environment assets included in the project
