#ifndef BABEL_MENU_H
#define BABEL_MENU_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int   active;
    int   player_name;
    int   player_box;
    int   player_health;
    int   player_distance;
    int   skeleton;
    float max_distance;
} DrawConfig;

typedef enum {
    AIM_NONE  = 0,
    AIM_HEAD  = 1,
    AIM_BODY  = 2,
    AIM_CHEST = 3
} AimTarget;

typedef struct {
    int       aim_assist;
    AimTarget target;
    float     max_angle;
    int       fov_enabled;
    int       fov_size;
} AimConfig;

typedef struct {
    DrawConfig draw;
    AimConfig  aim;
    int logo_x;
    int logo_y;
    int menu_open;
} BabelMenu;

void             babel_menu_init(BabelMenu *menu);
void             babel_menu_toggle(BabelMenu *menu);
void             babel_menu_close(BabelMenu *menu);
void             babel_menu_toggle_master(BabelMenu *menu);
void             babel_menu_toggle_draw_opt(int *field);
void             babel_menu_switch_tab(BabelMenu *menu, int tab);
void             babel_menu_set_distance(BabelMenu *menu, float metres);
void             babel_menu_toggle_aim(BabelMenu *menu);
void             babel_menu_select_aim(BabelMenu *menu, AimTarget target);
void             babel_menu_set_angle(BabelMenu *menu, float degrees);
void             babel_menu_toggle_fov(BabelMenu *menu);
void             babel_menu_set_fov_size(BabelMenu *menu, int size);
void             babel_menu_move_logo(BabelMenu *menu, int nx, int ny, int vw, int vh);
const BabelMenu *babel_menu_get_state(const BabelMenu *menu);
void             babel_menu_dump(const BabelMenu *menu);

/* Slider percentages (0-100) */
float babel_menu_distance_pct(const BabelMenu *menu);
float babel_menu_angle_pct(const BabelMenu *menu);
float babel_menu_fov_pct(const BabelMenu *menu);
float babel_menu_fov_radius(const BabelMenu *menu);

#ifdef __cplusplus
}
#endif

#endif
