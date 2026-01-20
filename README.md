# ClassPower

A comprehensive buff management addon for World of Warcraft 1.12.1. ClassPower simplifies raid-wide buff management for **Priests**, **Druids**, and **Paladins**.

## Features at a Glance

- **3 Fully Implemented Class Modules**: Priest, Druid, and Paladin
- **Admin Window**: Raid leaders can view and modify ANY class's assignments
- **Buff Synchronization**: Assignments sync automatically with other ClassPower users
- **Smart HUD**: Only shows buttons for buffs that need casting
- **Performance Optimized**: Minimal CPU usage with dirty-flag update system

---

## Class Modules

### Priest Module
Manage group-wide buffs and Turtle WoW's Champion system:

| Buff Type | Spells |
|-----------|--------|
| **Fortitude** | Power Word: Fortitude / Prayer of Fortitude |
| **Spirit** | Divine Spirit / Prayer of Spirit |
| **Shadow Protection** | Shadow Protection / Prayer of Shadow Protection |
| **Champion** | Proclaim, Grace, Empower, Revive Champion |
| **Enlighten** | Turtle WoW spell |

<img width="684" height="560" alt="PriestModule" src="https://github.com/user-attachments/assets/41dd97ce-fb4d-4f33-94bb-d9432f01639e" />

### Druid Module
Manage Mark of the Wild, Thorns assignments, and utility spells:

| Buff Type | Description |
|-----------|-------------|
| **Mark of the Wild** | Gift of the Wild for group buffs |
| **Thorns** | Customizable target list with priority system |
| **Emerald Blessing** | Turtle WoW spell |
| **Innervate** | Assign a target with mana threshold alerts |

<img width="722" height="186" alt="DruidModule" src="https://github.com/user-attachments/assets/4bfd6bab-3edf-41df-b9d8-0f3651e5f501" />

### Paladin Module
Class-based Greater Blessings, Auras, and Judgements:

| Feature | Details |
|---------|---------|
| **Greater Blessings** | Assigned per CLASS (not group): Wisdom, Might, Kings, Salvation, Sanctuary, Light |
| **Auras** | Devotion, Retribution, Concentration, Resistance Auras, Sanctity |
| **Judgements** | Light, Wisdom, Crusader, Justice |
| **Smart Buffs** | Won't suggest Wisdom for Warriors/Rogues, or Might for casters |
| **Symbol Tracking** | Shows Symbol of Kings reagent count |

<img width="1013" height="223" alt="PallyModule" src="https://github.com/user-attachments/assets/cb08f6d1-cde0-4c47-8c0f-1b42a80b218c" />

---

## Admin Module

The **Admin Window** allows **Raid Leaders** and **Raid Assistants** to view and modify buff assignments for ALL classes—not just their own.

### Opening the Admin Window
- **Command**: `/cpwr admin`
- **Minimap Button**: Shift + Left-click the ClassPower minimap button

<img width="461" height="180" alt="adminpanel" src="https://github.com/user-attachments/assets/e7351a77-55ac-434a-87f8-8a8e80e0495d" />

### Admin Window Features

| Button | Action |
|--------|--------|
| **Priests** | Opens Priest assignment grid |
| **Druids** | Opens Druid assignment grid |
| **Paladins** | Opens Paladin assignment grid |
| **Mages** | (Coming soon - greyed out) |
| **Shamans** | (Coming soon - greyed out) |
| **Manage Tanks** | Opens Tank Manager for priority assignments |

### How It Works

1. **Open Admin**: Use `/cpwr admin` or Shift-click the minimap button
2. **Select a Class**: Click on the class icon (e.g., "Priests")
3. **View Assignments**: The full configuration window for that class opens
4. **Make Changes**: Modify assignments as needed (requires Leader/Assist)
5. **Auto-Sync**: Changes broadcast automatically to all ClassPower users

> **Note**: Non-leaders can only view their own class's assignments. Raid Leaders/Assistants can view and edit ALL class modules.

### Tank Manager

Access via the Admin window's "Manage Tanks" button:

- **Add Target**: Click with a target selected, or use dropdown to pick from raid
- **Role Assignment**: Toggle between MT (Main Tank) and OT (Off-Tank)
- **Raid Markers**: Assign raid icons to tanks for visual identification
- **Announce**: Broadcast tank assignments to raid chat

---

## HUD (BuffBar)

The HUD shows which buffs need to be cast on your assigned groups/classes.

### HUD Controls

| Action | Result |
|--------|--------|
| Left-click buff icon | Cast Prayer/Gift/Greater Blessing |
| Right-click buff icon | Cast single-target buff |
| Shift-click assignment | Toggle all buffs at once (Priest) |
| Drag BuffBar title | Move the HUD |
| Drag corner grip | Resize/scale the HUD |
| Right-click minimap button | Toggle HUD visibility |

Icons disappear once everyone in your assigned group/class has the buff.

---

## Commands

### General Commands
| Command | Description |
|---------|-------------|
| `/cpwr` | Open configuration window for your class |
| `/cpwr admin` | Open Admin window (Leaders/Assistants) |
| `/cpwr reset` | Reset UI positions and scale |
| `/cpwr debug` | Toggle debug logging |
| `/cpwr scale <0.5-2.0>` | Set configuration window scale |

### Priest Commands
| Command | Description |
|---------|-------------|
| `/cpwr revive` | Cast Revive Champion on assigned target |
| `/cpwr checkbuffs` | Debug: list buffs on current target |

### Druid Commands
| Command | Description |
|---------|-------------|
| `/cpwr innervate` | Cast Innervate on assigned target |
| `/cpwr thorns` | Cast Thorns on next person missing it |
| `/cpwr emerald` | Cast Emerald Blessing |

### Paladin Commands
| Command | Description |
|---------|-------------|
| `/cpwr report` | Announce assignments to raid chat |
| `/cpwr checkbuffs` | Debug: list buffs on current target |

### Legacy Aliases
These still work for backwards compatibility:
- `/classpower`
- `/prip`, `/prp`, `/priestpower`

---

## Configuration Guide

### Initial Setup

1. **Open Config**: Type `/cpwr` to open your class's assignment window
2. **Assign Groups/Classes**: Click icons to toggle assignments
3. **Show HUD**: The BuffBar appears automatically when you have assignments

### Class-Specific Configuration

#### Priest
- Click individual buff icons to assign groups (1-8)
- **Shift-click** a group to toggle all 3 buffs simultaneously
- Assign a **Champion** target via the dropdown

#### Druid
- Click MotW icons to assign groups for Gift of the Wild
- Click **Thorns** button to manage your thorns target list
- Use the slider to set **Innervate mana threshold**

#### Paladin
- Click blessing icons to cycle through blessing types per class
- Use **mouse wheel** on class icons to quickly cycle blessings
- Assign your **Aura** and **Judgement** responsibilities

---

## Display Settings

Access via the gear icon on your config window:

| Setting | Description |
|---------|-------------|
| **Show when buffs missing** | HUD only shows when buffs are needed |
| **Show before expiration** | HUD shows when buffs are about to expire |
| **Always show with timers** | HUD always visible with countdown timers |
| **Timer Threshold** | Set minutes/seconds before expiration to show |

---

## Performance

ClassPower is designed to be lightweight:

| Operation | Frequency |
|-----------|-----------|
| Spell scanning | Only on `SPELLS_CHANGED` event |
| Buff scanning | Every 5 seconds (when UI visible) |
| UI updates | Only when data changes (dirty flag) |
| Sync messages | Throttled to prevent spam |

---

## Installation

1. Download the addon
2. Extract the `PriestPower` folder to `Interface\AddOns\`
3. Ensure the folder is named exactly `PriestPower`
4. Reload the game with `/reload`

---

## Credits

- Inspired by **PallyPower** by Relar/Sneakyfoot
- Originally developed as PriestPower, expanded to support multiple classes

## Support

Feedback and feature suggestions welcome!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-yellow)](https://buymeacoffee.com/slimewizzard)
