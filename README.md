# ClassPower (formerly PriestPower)

ClassPower is a buff management addon for World of Warcraft 1.12.1 (Turtle WoW). Inspired by the classic PallyPower, it simplifies raid-wide buff management for multiple classes.

## Supported Classes

### Priest Module
- **Power Word: Fortitude** / Prayer of Fortitude
- **Divine Spirit** / Prayer of Spirit
- **Shadow Protection** / Prayer of Shadow Protection
- **Champion Spells** (Turtle WoW): Proclaim, Grace, Empower, Revive
- **Enlighten** (Turtle WoW)

### Druid Module
- **Mark of the Wild** / Gift of the Wild
- **Thorns** (with customizable target list)
- **Emerald Blessing** (Turtle WoW)
- **Innervate** (with mana threshold alerts)

### Paladin Module
- **Greater Blessings** assigned by **Class** (not group):
  - Wisdom, Might, Kings, Salvation, Sanctuary, Light
- **Aura Assignments**: Devotion, Retribution, Concentration, Resistance Auras, Sanctity
- **Judgement Assignments**: Light, Wisdom, Crusader, Justice
- **Symbol of Kings tracking**
- **Smart Buffs**: Won't suggest Wisdom for Warriors/Rogues, Might for casters

## Features

- **Smart Buff Management**: Easily assign and track buffs across raid groups or classes.
- **Performance Optimized**:
  - Spell scanning only on `SPELLS_CHANGED` event
  - Buff scanning every 5 seconds (only when UI is visible)
  - Dirty flag system for efficient UI updates
- **Modern HUD (BuffBar)**:
  - **Dynamic Scaling**: Drag the bottom-right corner to resize.
  - **Smart Visibility**: Only shows buttons for missing buffs.
  - **Quick Casting**: Left-click for group/greater buff, Right-click for single target.
- **Raid Coordination**: Syncs assignments with other ClassPower users.
- **Greater Buff Detection**: Properly detects both normal and greater versions of buffs.

## HUD Usage

| Action | Result |
|--------|--------|
| Left-click buff icon | Cast Prayer/Gift/Greater Blessing |
| Right-click buff icon | Cast single-target buff |
| Shift-click assignment | Toggle all buffs at once (Priest) |
| Left-click + drag BuffBar | Move the HUD |
| Drag corner grip | Resize/scale the HUD |

Icons disappear once everyone in your assigned group/class has the buff.

## Commands

### General
- `/cpwr` or `/classpower`: Toggle the Configuration window for your class.
- `/cpwr reset`: Reset UI position and scale to defaults.
- `/cpwr debug`: Toggle debug logging.

### Priest-specific
- `/cpwr revive`: Cast Revive Champion on your assigned target.
- `/cpwr checkbuffs`: Debug command to list buffs on current target.

### Druid-specific
- `/cpwr innervate`: Cast Innervate on your assigned target.
- `/cpwr thorns`: Cast Thorns on the next person in your list missing it.
- `/cpwr emerald`: Cast Emerald Blessing.

### Paladin-specific
- `/cpwr report`: Report all paladin assignments to raid/party chat.
- `/cpwr checkbuffs`: Debug command to list buffs on current target.

### Legacy aliases
- `/prip`, `/prp`, `/priestpower`: Work as before for Priest module.

## Configuration

1. Use `/cpwr` to open the assignment grid for your class.
2. Click icons to toggle assignments:
   - **Priest**: Click individual buff icons, or Shift-click to toggle all 3.
   - **Druid**: Click MotW icons to assign groups, click Thorns to manage target list.
   - **Paladin**: Click blessing icons to cycle through blessing types per class.
3. Assignments sync automatically with other players using ClassPower.
4. Scale the UI by dragging the resize grip (bottom-right corner).

### Druid-specific Features
- **Thorns List**: Click the Thorns button to add/remove specific players.
- **Innervate Threshold**: Use the slider to set a mana % threshold.

### Paladin-specific Features
- **Class-based Blessings**: Assign Greater Blessings per class (Warrior, Rogue, Priest, etc.)
- **Aura Coordination**: Assign which aura each paladin should use.
- **Judgement Coordination**: Assign which judgement each paladin is responsible for.
- **Smart Buffs**: Automatically skips inappropriate blessings (e.g., Wisdom for Warriors).
- **Symbol Tracking**: Shows how many Symbols of Kings each paladin has.
- **Mouse Wheel**: Scroll on class icons to quickly cycle through blessings.

### Paladin-specific Features
- **Per-Class Blessings**: Assign different blessings to each class.
- **Aura Selection**: Choose which aura to maintain.
- **Judgement Tracking**: Coordinate judgements with other paladins.

## Installation

1. Download the addon.
2. Extract the `PriestPower` folder into your `Interface\AddOns` directory.
3. Ensure the folder name is exactly `PriestPower`.

## Performance

ClassPower is designed to be lightweight:
- **Spell scanning**: Only when you learn/unlearn spells
- **Buff scanning**: Every 5 seconds when UI is visible
- **UI updates**: Only when data actually changes (dirty flag system)

## Credits

- Inspired by **PallyPower** by Relar/Sneakyfoot.
- Originally developed as PriestPower, expanded to support multiple classes.

## Support

- Feedback and feature suggestions welcome!
- https://buymeacoffee.com/slimewizzard
