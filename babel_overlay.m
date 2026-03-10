/*
 * babel_overlay.m  — v4
 *
 * Overlay Metal injecté dans un jeu macOS Metal.
 *
 *  Logo "B"   → draggable à la souris (global + local monitor)
 *  Clic logo  → ouvre/ferme le menu
 *  F1 / ESC   → toggle / fermer
 *  ← →        → changer tab DRAW / AIM
 *  Clics menu → toggles ESP, aim, FOV, tabs
 *
 * Compile :
 *   clang -dynamiclib -fPIC -fobjc-arc -O2 \
 *         -framework Metal -framework Cocoa -framework QuartzCore \
 *         -o libbabel_overlay.dylib babel_overlay.m babel_menu.c -lm
 *
 * Inject :
 *   DYLD_INSERT_LIBRARIES=./libbabel_overlay.dylib ./LeJeu
 */

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <math.h>
#include "babel_menu.h"

/* ══════════════════════════════════════════════════════
   SHADERS MSL
   ══════════════════════════════════════════════════════ */
static NSString *kMSL = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct V { float2 p [[attribute(0)]]; float4 c [[attribute(1)]]; };\n"
    "struct F { float4 p [[position]]; float4 c; };\n"
    "vertex F vmain(V in [[stage_in]]) {\n"
    "    F o; o.p=float4(in.p,0,1); o.c=in.c; return o; }\n"
    "fragment float4 fmain(F in [[stage_in]]) { return in.c; }\n";

/* ══════════════════════════════════════════════════════
   ETAT GLOBAL
   ══════════════════════════════════════════════════════ */
static BabelMenu                  g_menu;
static id<MTLRenderPipelineState> g_pso   = nil;
static id<MTLBuffer>              g_vbuf  = nil;
static BOOL                       g_ready = NO;
static float                      g_vpW   = 1920.f;
static float                      g_vpH   = 1080.f;
static int                        g_tab   = 0;

/* ── Drag logo ── */
static BOOL  g_drag     = NO;
static BOOL  g_did_drag = NO;
static float g_drag_sx  = 0;
static float g_drag_sy  = 0;
static float g_drag_ox  = 0;
static float g_drag_oy  = 0;

static id g_mon_key = nil;
static id g_mon_dn  = nil;
static id g_mon_mv  = nil;
static id g_mon_up  = nil;

/* ══════════════════════════════════════════════════════
   VERTEX BUFFER CPU
   ══════════════════════════════════════════════════════ */
typedef struct { float x,y,r,g,b,a; } V6;
#define MAX_V 8192
static V6  g_v[MAX_V];
static int g_nv = 0;

static void vb_reset(void) { g_nv = 0; }

static void vp(float x,float y,float r,float g,float b,float a)
{
    if (g_nv >= MAX_V) return;
    g_v[g_nv++] = (V6){ 2.f*x/g_vpW-1.f, -2.f*y/g_vpH+1.f, r,g,b,a };
}

/* ══════════════════════════════════════════════════════
   PRIMITIVES 2D
   ══════════════════════════════════════════════════════ */
#define GR 0.961f
#define GG 0.773f
#define GB 0.094f

static void fill(float x,float y,float w,float h,
                 float r,float g,float b,float a)
{
    vp(x,  y,  r,g,b,a); vp(x+w,y,  r,g,b,a); vp(x,  y+h,r,g,b,a);
    vp(x+w,y,  r,g,b,a); vp(x+w,y+h,r,g,b,a); vp(x,  y+h,r,g,b,a);
}

static void border(float x,float y,float w,float h,float t,
                   float r,float g,float b,float a)
{
    fill(x,    y,     w, t, r,g,b,a);
    fill(x,    y+h-t, w, t, r,g,b,a);
    fill(x,    y,     t, h, r,g,b,a);
    fill(x+w-t,y,     t, h, r,g,b,a);
}

static void circ(float cx,float cy,float rad,
                 float r,float g,float b,float a,
                 BOOL filled,int seg)
{
    float s = 2.f*(float)M_PI/seg;
    for (int i=0;i<seg;i++) {
        float a0=i*s, a1=(i+1)*s;
        float x0=cx+cosf(a0)*rad, y0=cy+sinf(a0)*rad;
        float x1=cx+cosf(a1)*rad, y1=cy+sinf(a1)*rad;
        if (filled) {
            vp(cx,cy,r,g,b,a); vp(x0,y0,r,g,b,a); vp(x1,y1,r,g,b,a);
        } else {
            float t=1.5f;
            float ix0=cx+cosf(a0)*(rad-t), iy0=cy+sinf(a0)*(rad-t);
            float ix1=cx+cosf(a1)*(rad-t), iy1=cy+sinf(a1)*(rad-t);
            vp(x0,y0,r,g,b,a); vp(x1,y1,r,g,b,a); vp(ix0,iy0,r,g,b,a);
            vp(x1,y1,r,g,b,a); vp(ix1,iy1,r,g,b,a); vp(ix0,iy0,r,g,b,a);
        }
    }
}

static void toggle_pill(float x,float y,int on)
{
    fill(x,y,34,18, on?GR:0.2f, on?GG:0.2f, on?GB:0.2f, 1.f);
    circ(on ? x+25 : x+9, y+9, 7, 1,1,1,1, YES,16);
}

static void radio_dot(float cx,float cy,int on)
{
    circ(cx,cy,7, on?GR:0.33f,on?GG:0.33f,on?GB:0.33f,1.f,NO,16);
    if (on) circ(cx,cy,4, GR,GG,GB,1.f,YES,16);
}

static void slider_track(float x,float y,float w,float pct)
{
    fill(x,y,w,4, 0.2f,0.2f,0.2f,1.f);
    fill(x,y,w*pct,4, GR,GG,GB,1.f);
    circ(x+w*pct,y+2,6, GR,GG,GB,1.f,YES,16);
}

static void draw_B(float lx,float ly)
{
    fill(lx+18,ly+15, 3,20, GR,GG,GB,1.f);
    fill(lx+21,ly+15, 8, 2, GR,GG,GB,1.f);
    fill(lx+21,ly+23, 8, 2, GR,GG,GB,1.f);
    fill(lx+29,ly+17, 2, 6, GR,GG,GB,1.f);
    fill(lx+21,ly+23,10, 2, GR,GG,GB,1.f);
    fill(lx+21,ly+33,10, 2, GR,GG,GB,1.f);
    fill(lx+31,ly+25, 2, 8, GR,GG,GB,1.f);
}

/* ══════════════════════════════════════════════════════
   GEOMETRIE COMPLETE
   ══════════════════════════════════════════════════════ */
static void build_geo(void)
{
    vb_reset();

    float lx = (float)g_menu.logo_x;
    float ly = (float)g_menu.logo_y;

    /* Logo */
    circ(lx+25,ly+25,25, 0.067f,0.067f,0.067f,1.f,YES,32);
    circ(lx+25,ly+25,25, GR,GG,GB,1.f,NO,32);
    draw_B(lx,ly);

    if (!g_menu.menu_open) return;

    fill(0,0,g_vpW,g_vpH, 0,0,0,0.92f);

    float mx = (g_vpW-300)*.5f;
    float my = (g_vpH-480)*.5f;

    fill  (mx,my,300,480, 0.067f,0.067f,0.067f,1.f);
    border(mx,my,300,480,2, GR,GG,GB,1.f);

    /* Tabs */
    fill(mx,    my,150,36, g_tab==0?GR:0.102f,g_tab==0?GG:0.102f,g_tab==0?GB:0.102f,1.f);
    fill(mx+150,my,150,36, g_tab==1?GR:0.102f,g_tab==1?GG:0.102f,g_tab==1?GB:0.102f,1.f);
    fill(mx,my+36,300,1, 0.133f,0.133f,0.133f,1.f);

    float row = my+44;

    /* ── TAB DRAW ── */
    if (g_tab==0) {
        fill(mx+12,row,80,2,GR,GG,GB,0.5f); row+=14;
        fill(mx,row,300,32,0.067f,0.067f,0.067f,1.f);
        toggle_pill(mx+254,row+7, g_menu.draw.active);
        fill(mx,row+31,300,1,0.133f,0.133f,0.133f,1.f); row+=32;

        float sa = g_menu.draw.active?1.f:0.3f;
        int opts[5] = {g_menu.draw.player_name, g_menu.draw.player_box,
                       g_menu.draw.player_health, g_menu.draw.player_distance,
                       g_menu.draw.skeleton};
        for (int i=0;i<5;i++) {
            fill(mx,row,300,30,0.067f,0.067f,0.067f,sa);
            fill(mx+254,row+6,34,18, opts[i]?GR:0.2f,opts[i]?GG:0.2f,opts[i]?GB:0.2f,sa);
            circ(opts[i]?mx+279:mx+263, row+15, 7, 1,1,1,sa,YES,16);
            fill(mx,row+29,300,1,0.133f,0.133f,0.133f,1.f); row+=30;
        }
        fill(mx+12,row,80,2,GR,GG,GB,0.5f); row+=16;
        slider_track(mx+12,row+4,276, babel_menu_distance_pct(&g_menu)/100.f);
    }

    /* ── TAB AIM ── */
    else {
        fill(mx+12,row,80,2,GR,GG,GB,0.5f); row+=14;
        fill(mx,row,300,32,0.067f,0.067f,0.067f,1.f);
        toggle_pill(mx+254,row+7, g_menu.aim.aim_assist);
        fill(mx,row+31,300,1,0.133f,0.133f,0.133f,1.f); row+=32;

        AimTarget bv[3]={AIM_HEAD,AIM_BODY,AIM_CHEST};
        for (int i=0;i<3;i++) {
            fill(mx,row,300,30,0.067f,0.067f,0.067f,1.f);
            radio_dot(mx+278,row+15, g_menu.aim.target==bv[i]);
            fill(mx,row+29,300,1,0.133f,0.133f,0.133f,1.f); row+=30;
        }
        fill(mx+12,row,80,2,GR,GG,GB,0.5f); row+=16;
        slider_track(mx+12,row+4,276, babel_menu_angle_pct(&g_menu)/100.f);
        row+=24;

        fill(mx+12,row,60,2,GR,GG,GB,0.5f); row+=14;
        fill(mx,row,300,32,0.067f,0.067f,0.067f,1.f);
        toggle_pill(mx+254,row+7, g_menu.aim.fov_enabled);
        fill(mx,row+31,300,1,0.133f,0.133f,0.133f,1.f); row+=32;
        slider_track(mx+12,row+4,276, babel_menu_fov_pct(&g_menu)/100.f);
        row+=24;

        if (g_menu.aim.fov_enabled) {
            float fr=babel_menu_fov_radius(&g_menu);
            float fcx=mx+150, fcy=row+55;
            circ(fcx,fcy,fr,GR,GG,GB,0.07f,YES,48);
            circ(fcx,fcy,fr,GR,GG,GB,1.f,NO,48);
            fill(fcx-8,fcy-.75f,16,1.5f,GR,GG,GB,0.8f);
            fill(fcx-.75f,fcy-8,1.5f,16,GR,GG,GB,0.8f);
        }
    }
}

/* ══════════════════════════════════════════════════════
   INIT PIPELINE METAL
   ══════════════════════════════════════════════════════ */
static void init_metal(id<MTLDevice> dev, MTLPixelFormat fmt)
{
    if (g_ready) return;
    NSError *e=nil;
    id<MTLLibrary> lib=[dev newLibraryWithSource:kMSL options:nil error:&e];
    if (!lib){NSLog(@"[Babel] Shader: %@",e);return;}

    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];
    pd.vertexFunction  =[lib newFunctionWithName:@"vmain"];
    pd.fragmentFunction=[lib newFunctionWithName:@"fmain"];
    pd.colorAttachments[0].pixelFormat                 =fmt;
    pd.colorAttachments[0].blendingEnabled             =YES;
    pd.colorAttachments[0].sourceRGBBlendFactor        =MTLBlendFactorSourceAlpha;
    pd.colorAttachments[0].destinationRGBBlendFactor   =MTLBlendFactorOneMinusSourceAlpha;
    pd.colorAttachments[0].sourceAlphaBlendFactor      =MTLBlendFactorOne;
    pd.colorAttachments[0].destinationAlphaBlendFactor =MTLBlendFactorOneMinusSourceAlpha;

    MTLVertexDescriptor *vd=[MTLVertexDescriptor new];
    vd.attributes[0].format=MTLVertexFormatFloat2;vd.attributes[0].offset=0;vd.attributes[0].bufferIndex=0;
    vd.attributes[1].format=MTLVertexFormatFloat4;vd.attributes[1].offset=8;vd.attributes[1].bufferIndex=0;
    vd.layouts[0].stride=sizeof(V6);
    pd.vertexDescriptor=vd;

    g_pso =[dev newRenderPipelineStateWithDescriptor:pd error:&e];
    g_vbuf=[dev newBufferWithLength:sizeof(g_v) options:MTLResourceStorageModeShared];
    g_ready=YES;
    NSLog(@"[Babel] Metal pret ✓");
}

static void render_overlay(id<MTLCommandBuffer> cb,id<MTLTexture> tex,MTLPixelFormat fmt)
{
    init_metal(cb.device,fmt);
    if (!g_ready) return;
    g_vpW=(float)tex.width; g_vpH=(float)tex.height;
    build_geo();
    if (!g_nv) return;
    memcpy(g_vbuf.contents,g_v,g_nv*sizeof(V6));

    MTLRenderPassDescriptor *rpd=[MTLRenderPassDescriptor new];
    rpd.colorAttachments[0].texture    =tex;
    rpd.colorAttachments[0].loadAction =MTLLoadActionLoad;
    rpd.colorAttachments[0].storeAction=MTLStoreActionStore;

    id<MTLRenderCommandEncoder> enc=[cb renderCommandEncoderWithDescriptor:rpd];
    [enc setRenderPipelineState:g_pso];
    [enc setVertexBuffer:g_vbuf offset:0 atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:g_nv];
    [enc endEncoding];
}

/* ══════════════════════════════════════════════════════
   HOOK presentDrawable:
   ══════════════════════════════════════════════════════ */
@interface BabelHook : NSObject @end
@implementation BabelHook
-(void)babel_presentDrawable:(id<MTLDrawable>)d {
    if ([d conformsToProtocol:@protocol(CAMetalDrawable)]) {
        id<CAMetalDrawable> md=(id<CAMetalDrawable>)d;
        render_overlay((id<MTLCommandBuffer>)self,md.texture,md.texture.pixelFormat);
    }
    [self babel_presentDrawable:d];
}
@end

/* ══════════════════════════════════════════════════════
   COORDONNEES SOURIS
   ══════════════════════════════════════════════════════ */
static void ev_pos(NSEvent *ev,float *ox,float *oy)
{
    NSPoint p=ev.locationInWindow;
    if (ev.window) p=[ev.window convertPointToScreen:p];
    CGFloat sh=[NSScreen mainScreen].frame.size.height;
    *ox=(float)p.x;
    *oy=(float)(sh-p.y);
}

static BOOL hit_logo(float px,float py)
{
    float cx=g_menu.logo_x+25.f, cy=g_menu.logo_y+25.f;
    float dx=px-cx, dy=py-cy;
    return dx*dx+dy*dy<=625.f;
}

/* ══════════════════════════════════════════════════════
   CLICS MENU
   ══════════════════════════════════════════════════════ */
static void handle_menu_click(float cx,float cy)
{
    if (!g_menu.menu_open) return;
    float mx=(g_vpW-300)*.5f, my=(g_vpH-480)*.5f;

    if (cy>=my && cy<=my+36) {
        if (cx>=mx     && cx<=mx+150) g_tab=0;
        if (cx>=mx+150 && cx<=mx+300) g_tab=1;
        return;
    }

    float row=my+58;
    if (g_tab==0) {
        if (cy>=row && cy<=row+32){babel_menu_toggle_master(&g_menu);return;} row+=32;
        int *f[5]={&g_menu.draw.player_name,&g_menu.draw.player_box,
                   &g_menu.draw.player_health,&g_menu.draw.player_distance,
                   &g_menu.draw.skeleton};
        for (int i=0;i<5;i++){
            if (cy>=row && cy<=row+30){babel_menu_toggle_draw_opt(f[i]);return;}
            row+=30;
        }
    } else {
        if (cy>=row && cy<=row+32){babel_menu_toggle_aim(&g_menu);return;} row+=32;
        AimTarget bt[3]={AIM_HEAD,AIM_BODY,AIM_CHEST};
        for (int i=0;i<3;i++){
            if (cy>=row && cy<=row+30){babel_menu_select_aim(&g_menu,bt[i]);return;}
            row+=30;
        }
        row+=40;
        if (cy>=row && cy<=row+32) babel_menu_toggle_fov(&g_menu);
    }
}

/* ══════════════════════════════════════════════════════
   SETUP SOURIS — drag + clic
   ══════════════════════════════════════════════════════ */
/* handler partagé mouseDown — utilisé par global ET local monitor */
static void on_mouse_down(NSEvent *ev)
{
    float px,py; ev_pos(ev,&px,&py);
    if (hit_logo(px,py)){
        g_drag=YES; g_did_drag=NO;
        g_drag_sx=px; g_drag_sy=py;
        g_drag_ox=(float)g_menu.logo_x;
        g_drag_oy=(float)g_menu.logo_y;
    }
}

static void on_mouse_drag(NSEvent *ev)
{
    if (!g_drag) return;
    float px,py; ev_pos(ev,&px,&py);
    float dx=px-g_drag_sx, dy=py-g_drag_sy;
    if (fabsf(dx)>3.f||fabsf(dy)>3.f) g_did_drag=YES;
    babel_menu_move_logo(&g_menu,
        (int)(g_drag_ox+dx),(int)(g_drag_oy+dy),
        (int)g_vpW,(int)g_vpH);
}

static void on_mouse_up(NSEvent *ev)
{
    float px,py; ev_pos(ev,&px,&py);
    if (g_drag){
        g_drag=NO;
        if (!g_did_drag && hit_logo(px,py))
            babel_menu_toggle(&g_menu);
    } else {
        handle_menu_click(px,py);
    }
}

static void setup_mouse(void)
{
    /* Global monitors : reçoivent les events même quand
       le jeu a le focus (nécessite Accessibility permission) */
    g_mon_dn=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
        handler:^(NSEvent *ev){ on_mouse_down(ev); }];

    g_mon_mv=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDragged
        handler:^(NSEvent *ev){ on_mouse_drag(ev); }];

    g_mon_up=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp
        handler:^(NSEvent *ev){ on_mouse_up(ev); }];

    /* Local monitors : fallback si Accessibility non accordé
       (reçoit les events quand notre process est au premier plan) */
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
        handler:^NSEvent*(NSEvent *ev){ on_mouse_down(ev); return ev; }];

    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDragged
        handler:^NSEvent*(NSEvent *ev){ on_mouse_drag(ev); return ev; }];

    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp
        handler:^NSEvent*(NSEvent *ev){ on_mouse_up(ev); return ev; }];
}

/* ══════════════════════════════════════════════════════
   SETUP CLAVIER
   ══════════════════════════════════════════════════════ */
static void setup_keyboard(void)
{
    g_mon_key=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown
        handler:^(NSEvent *ev){
            switch(ev.keyCode){
                case 122: babel_menu_toggle(&g_menu); break;    /* F1  */
                case 53:  babel_menu_close(&g_menu);  break;    /* ESC */
                case 123: if(g_menu.menu_open) g_tab=0; break;  /* ←   */
                case 124: if(g_menu.menu_open) g_tab=1; break;  /* →   */
            }
        }];
}

/* ══════════════════════════════════════════════════════
   CONSTRUCTOR / DESTRUCTOR
   ══════════════════════════════════════════════════════ */
__attribute__((constructor))
static void babel_inject(void)
{
    NSLog(@"[Babel] Injection v3 ✓");
    babel_menu_init(&g_menu);

    Class cls=objc_getClass("MTLCommandBufferAccessor");
    if (!cls) cls=objc_getClass("MTLDebugCommandBuffer");
    if (!cls) cls=objc_getClass("MTLCommandBuffer");

    if (cls){
        SEL orig=@selector(presentDrawable:);
        SEL hook=@selector(babel_presentDrawable:);
        Method om=class_getInstanceMethod(cls,orig);
        Method hm=class_getInstanceMethod([BabelHook class],hook);
        if (om&&hm){method_exchangeImplementations(om,hm);NSLog(@"[Babel] Hook actif ✓");}
        else NSLog(@"[Babel] ⚠ Hook echoue");
    }

    dispatch_async(dispatch_get_main_queue(),^{
        setup_keyboard();
        setup_mouse();
        NSLog(@"[Babel] Clic logo = toggle | Drag logo = deplacer | F1/ESC = toggle/fermer | ←→ = tabs");
    });
}

__attribute__((destructor))
static void babel_eject(void)
{
    if(g_mon_key)[NSEvent removeMonitor:g_mon_key];
    if(g_mon_dn) [NSEvent removeMonitor:g_mon_dn];
    if(g_mon_mv) [NSEvent removeMonitor:g_mon_mv];
    if(g_mon_up) [NSEvent removeMonitor:g_mon_up];
    NSLog(@"[Babel] Ejecte");
}
