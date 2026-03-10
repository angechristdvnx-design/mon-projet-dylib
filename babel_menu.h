#ifndef BABEL_MENU_H
#define BABEL_MENU_H

#ifdef __cplusplus
extern "C" {
#endif

/* ── State structs ── */

typedef struct {
    int  active;          /* ESP Visual master toggle */
    int  player_name;
    int  player_box;
    int  player_health;
    int  player_distance;
    int  skeleton;
    float max_distance;   /* metres, 50–500 */
} DrawConfig;

typedef enum {
    AIM_NONE  = 0,
    AIM_HEAD  = 1,
    AIM_BODY  = 2,
    AIM_CHEST = 3
} AimTarget;

typedef struct {
    int        aim_assist;   /* master toggle */
    AimTarget  target;
    float      max_angle;    /* degrees, 1–180 */
    int        fov_enabled;
    int        fov_size;     /* 10–300 */
} AimConfig;

typedef struct {
    DrawConfig draw;
    AimConfig  aim;
    /* logo position (pixels) */
    int logo_x;
    int logo_y;
    int menu_open;
} BabelMenu;

/* ── API ── */

/**
 * Initialise the menu with default values.
 * Must be called before any other function.
 */
void babel_menu_init(BabelMenu *menu);

/** Toggle the overlay visibility. */
void babel_menu_toggle(BabelMenu *menu);

/** Close the overlay. */
void babel_menu_close(BabelMenu *menu);

/** Toggle the ESP visual master switch. */
void babel_menu_toggle_master(BabelMenu *menu);

/** Toggle an individual draw sub-option (0 = off, 1 = on).
 *  field_offset = offsetof(DrawConfig, field) */
void babel_menu_toggle_draw_opt(int *field);

/** Switch the active tab (0 = DRAW, 1 = AIM). */
void babel_menu_switch_tab(BabelMenu *menu, int tab);

/** Set the max detection distance (clamped to [50, 500]). */
void babel_menu_set_distance(BabelMenu *menu, float metres);

/** Toggle aim-assist master and clear selection if already on. */
void babel_menu_toggle_aim(BabelMenu *menu);

/** Select an aim target bone. Also enables aim_assist. */
void babel_menu_select_aim(BabelMenu *menu, AimTarget target);

/** Set the max angle (clamped to [1, 180]). */
void babel_menu_set_angle(BabelMenu *menu, float degrees);

/** Toggle FOV circle visibility. */
void babel_menu_toggle_fov(BabelMenu *menu);

/** Set the FOV size (clamped to [10, 300]). */
void babel_menu_set_fov_size(BabelMenu *menu, int size);

/**
 * Update logo drag position.
 * viewport_w / viewport_h = screen dimensions.
 */
void babel_menu_move_logo(BabelMenu *menu,
                          int new_x, int new_y,
                          int viewport_w, int viewport_h);

/** Return a read-only pointer to current state (convenience). */
const BabelMenu *babel_menu_get_state(const BabelMenu *menu);

/** Dump current state to stdout (debug helper). */
void babel_menu_dump(const BabelMenu *menu);

#ifdef __cplusplus
}
#endif

#endif /* BABEL_MENU_H */
