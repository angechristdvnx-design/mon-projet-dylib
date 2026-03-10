/*
 * babel_menu.c
 *
 * C translation of babel_menu_fixed.html
 * Implements the full ESP / Aim-assist menu logic.
 *
 * Build (macOS .dylib):
 *   clang -dynamiclib -fPIC -O2 -o libbabel_menu.dylib babel_menu.c
 *
 * Build (Linux .so – cross-compile for macOS .dylib emulation):
 *   gcc -shared -fPIC -O2 -o libbabel_menu.dylib babel_menu.c
 */

#include "babel_menu.h"

#include <stdio.h>
#include <string.h>
#include <math.h>   /* fminf / fmaxf */

/* ─────────────────────────────────────────
   Internal helpers
   ───────────────────────────────────────── */

static float clampf(float v, float lo, float hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static int clampi(int v, int lo, int hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

/* Slider fill percentage helper (mirrors JS updateSlider) */
static float slider_pct(float value, float min, float max)
{
    if (max == min) return 0.0f;
    return (value - min) / (max - min) * 100.0f;
}

/* ─────────────────────────────────────────
   babel_menu_init
   Mirrors the HTML default attribute values
   ───────────────────────────────────────── */
void babel_menu_init(BabelMenu *menu)
{
    if (!menu) return;
    memset(menu, 0, sizeof(*menu));

    /* DrawConfig defaults */
    menu->draw.active          = 1;   /* toggle.on present on Activate */
    menu->draw.player_name     = 0;
    menu->draw.player_box      = 0;
    menu->draw.player_health   = 0;
    menu->draw.player_distance = 0;
    menu->draw.skeleton        = 0;
    menu->draw.max_distance    = 200.0f;  /* input value="200" */

    /* AimConfig defaults */
    menu->aim.aim_assist  = 0;
    menu->aim.target      = AIM_NONE;
    menu->aim.max_angle   = 45.0f;    /* input value="45" */
    menu->aim.fov_enabled = 1;        /* toggle.on on FOV Circle */
    menu->aim.fov_size    = 100;      /* input value="100" */

    /* Logo default position */
    menu->logo_x   = 10;
    menu->logo_y   = 10;
    menu->menu_open = 0;
}

/* ─────────────────────────────────────────
   Menu visibility  (JS: toggleMenu / closeMenu)
   ───────────────────────────────────────── */
void babel_menu_toggle(BabelMenu *menu)
{
    if (!menu) return;
    menu->menu_open = !menu->menu_open;
}

void babel_menu_close(BabelMenu *menu)
{
    if (!menu) return;
    menu->menu_open = 0;
}

/* ─────────────────────────────────────────
   Master ESP toggle  (JS: toggleMaster)
   ───────────────────────────────────────── */
void babel_menu_toggle_master(BabelMenu *menu)
{
    if (!menu) return;
    menu->draw.active = !menu->draw.active;
    /*
     * When master is off, sub-options become visually dim
     * (opacity 0.3, pointer-events none).  In this C port
     * callers should check menu->draw.active before reading
     * any sub-option.
     */
}

/* ─────────────────────────────────────────
   Individual draw option toggle  (JS: toggleOpt)
   ───────────────────────────────────────── */
void babel_menu_toggle_draw_opt(int *field)
{
    if (!field) return;
    *field = !(*field);
}

/* ─────────────────────────────────────────
   Tab switch  (JS: switchTab)
   active_tab: 0 = DRAW, 1 = AIM
   ───────────────────────────────────────── */
void babel_menu_switch_tab(BabelMenu *menu, int tab)
{
    (void)menu;   /* tab state is purely UI; stored if needed */
    (void)tab;
    /* nothing to mutate in the data model; rendering layer
       uses this to show draw1/draw2 pane */
}

/* ─────────────────────────────────────────
   Distance slider  (JS: updateSlider with 'distVal')
   ───────────────────────────────────────── */
void babel_menu_set_distance(BabelMenu *menu, float metres)
{
    if (!menu) return;
    menu->draw.max_distance = clampf(metres, 50.0f, 500.0f);
}

/* slider_pct accessor for draw distance */
float babel_menu_distance_pct(const BabelMenu *menu)
{
    if (!menu) return 0.0f;
    return slider_pct(menu->draw.max_distance, 50.0f, 500.0f);
}

/* ─────────────────────────────────────────
   Aim toggle  (JS: toggleAimMenu)
   ───────────────────────────────────────── */
void babel_menu_toggle_aim(BabelMenu *menu)
{
    if (!menu) return;
    if (menu->aim.target != AIM_NONE) {
        /* clear selection, turn toggle off */
        menu->aim.target      = AIM_NONE;
        menu->aim.aim_assist  = 0;
    } else {
        menu->aim.aim_assist = !menu->aim.aim_assist;
    }
}

/* ─────────────────────────────────────────
   Aim bone selection  (JS: selectAim)
   ───────────────────────────────────────── */
void babel_menu_select_aim(BabelMenu *menu, AimTarget target)
{
    if (!menu) return;
    menu->aim.target     = target;
    menu->aim.aim_assist = (target != AIM_NONE) ? 1 : 0;
}

/* ─────────────────────────────────────────
   Angle slider  (JS: updateAngleSlider)
   ───────────────────────────────────────── */
void babel_menu_set_angle(BabelMenu *menu, float degrees)
{
    if (!menu) return;
    menu->aim.max_angle = clampf(degrees, 1.0f, 180.0f);
}

float babel_menu_angle_pct(const BabelMenu *menu)
{
    if (!menu) return 0.0f;
    return slider_pct(menu->aim.max_angle, 1.0f, 180.0f);
}

/* ─────────────────────────────────────────
   FOV toggle  (JS: toggleFOV)
   ───────────────────────────────────────── */
void babel_menu_toggle_fov(BabelMenu *menu)
{
    if (!menu) return;
    menu->aim.fov_enabled = !menu->aim.fov_enabled;
}

/* ─────────────────────────────────────────
   FOV size slider  (JS: updateFOVSlider)
   ───────────────────────────────────────── */
void babel_menu_set_fov_size(BabelMenu *menu, int size)
{
    if (!menu) return;
    menu->aim.fov_size = clampi(size, 10, 300);
}

float babel_menu_fov_pct(const BabelMenu *menu)
{
    if (!menu) return 0.0f;
    return slider_pct((float)menu->aim.fov_size, 10.0f, 300.0f);
}

/*
 * FOV canvas radius  (mirrors JS drawFOV logic)
 *   maxR = 65 pixels (canvas 150x150)
 *   r    = max(8, (fovSize/300) * maxR)
 */
float babel_menu_fov_radius(const BabelMenu *menu)
{
    if (!menu) return 8.0f;
    float r = ((float)menu->aim.fov_size / 300.0f) * 65.0f;
    return (r < 8.0f) ? 8.0f : r;
}

/* ─────────────────────────────────────────
   Logo drag  (JS: onMove)
   ───────────────────────────────────────── */
void babel_menu_move_logo(BabelMenu *menu,
                          int new_x, int new_y,
                          int viewport_w, int viewport_h)
{
    if (!menu) return;
    /* clamp: max(0, min(viewport - 60, value))  (logo 50px + 10px margin) */
    menu->logo_x = clampi(new_x, 0, viewport_w  - 60);
    menu->logo_y = clampi(new_y, 0, viewport_h - 60);
}

/* ─────────────────────────────────────────
   State accessor
   ───────────────────────────────────────── */
const BabelMenu *babel_menu_get_state(const BabelMenu *menu)
{
    return menu;
}

/* ─────────────────────────────────────────
   Debug dump
   ───────────────────────────────────────── */
static const char *aim_target_str(AimTarget t)
{
    switch (t) {
        case AIM_HEAD:  return "Head";
        case AIM_BODY:  return "Body";
        case AIM_CHEST: return "Chest";
        default:        return "None";
    }
}

void babel_menu_dump(const BabelMenu *menu)
{
    if (!menu) { puts("babel_menu_dump: NULL"); return; }

    printf("=== BabelMenu State ===\n");
    printf("  menu_open   : %s\n",  menu->menu_open ? "yes" : "no");
    printf("  logo pos    : (%d, %d)\n", menu->logo_x, menu->logo_y);

    printf("  [DRAW]\n");
    printf("    active        : %s\n", menu->draw.active        ? "ON"  : "OFF");
    printf("    player_name   : %s\n", menu->draw.player_name   ? "ON"  : "OFF");
    printf("    player_box    : %s\n", menu->draw.player_box     ? "ON"  : "OFF");
    printf("    player_health : %s\n", menu->draw.player_health  ? "ON"  : "OFF");
    printf("    player_dist   : %s\n", menu->draw.player_distance? "ON"  : "OFF");
    printf("    skeleton      : %s\n", menu->draw.skeleton       ? "ON"  : "OFF");
    printf("    max_distance  : %.0f M (%.1f%%)\n",
           menu->draw.max_distance,
           babel_menu_distance_pct(menu));

    printf("  [AIM]\n");
    printf("    aim_assist    : %s\n", menu->aim.aim_assist  ? "ON"  : "OFF");
    printf("    target        : %s\n", aim_target_str(menu->aim.target));
    printf("    max_angle     : %.0f° (%.1f%%)\n",
           menu->aim.max_angle,
           babel_menu_angle_pct(menu));
    printf("    fov_enabled   : %s\n", menu->aim.fov_enabled ? "ON"  : "OFF");
    printf("    fov_size      : %d   (%.1f%%)  radius=%.1f px\n",
           menu->aim.fov_size,
           babel_menu_fov_pct(menu),
           babel_menu_fov_radius(menu));
    printf("=======================\n");
}
