/*
 The 205 Flicks black-and-white settings panel. It is drawn straight
 onto the finished frame, so none of the post-processing touches it.

 The proxy can't take input away from the game, so while the panel is open an
 invisible window lies over the game. It catches the mouse without taking focus,
 and the game never sees those clicks.
*/
#include "common.h"
#include "post.h"
#include "ui.h"
#include <stdlib.h>
#include <string.h>
#include "flicks_logo.h"

#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_LINEAR 0x2601
#define GL_RGBA8 0x8058
#define GL_BGRA 0x80E1
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FLOAT 0x1406
#define GL_TRIANGLES 4
#define GL_BLEND 0x0BE2
#define GL_DEPTH_TEST 0x0B71
#define GL_CULL_FACE 0x0B44
#define GL_SCISSOR_TEST 0x0C11
#define GL_SAMPLE_ALPHA_TO_COVERAGE 0x809E
#define GL_SRC_ALPHA 0x0302
#define GL_ONE_MINUS_SRC_ALPHA 0x0303
#define GL_TEXTURE0 0x84C0
#define GL_ARRAY_BUFFER 0x8892
#define GL_STREAM_DRAW 0x88E0
#define GL_FRAMEBUFFER 0x8D40
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_VERTEX_SHADER 0x8B31
#define GL_LINK_STATUS 0x8B82

#define UNIT_FONT 17		/* above the post-processing units */
#define FONT_COLUMNS 16
#define FONT_ROWS 6
#define FONT_FIRST 32
#define FONT_LAST 126
#define MAX_QUADS 4096
#define MAX_PACKS 32
#define VERTEX_FLOATS 8

typedef struct {
	float r, g, b, a;
} color;

static const color TEXT_LIGHT={0.94f,0.94f,0.94f,1},TEXT_DARK={0.02f,0.02f,0.02f,1};
static const color SHADOW={0,0,0,0},ASTERISK={0.6f,0.6f,0.6f,1};
static const color LABEL_BOX={0.06f,0.06f,0.06f,1},LABEL_EDGE={0.06f,0.06f,0.06f,1};
static const color BUTTON_BOX={0.115f,0.115f,0.115f,1},BUTTON_EDGE={0.2f,0.2f,0.2f,1};
static const color SELECTED={0.92f,0.92f,0.92f,1},SELECTED_EDGE={0.92f,0.92f,0.92f,1};
static const color BAR={0.8f,0.8f,0.8f,1},DIM={0,0,0,0.35f};

static void (WINAPI *gl_Enable)(GLenum), (WINAPI *gl_Disable)(GLenum);
static GLboolean (WINAPI *gl_IsEnabled)(GLenum);
static void (WINAPI *gl_GetIntegerv)(GLenum, GLint *);
static void (WINAPI *gl_BlendFunc)(GLenum, GLenum);
static void (WINAPI *gl_Viewport)(GLint, GLint, GLsizei, GLsizei);
static void (WINAPI *gl_BindTexture)(GLenum, GLuint);
static void (WINAPI *gl_GenTextures)(GLsizei, GLuint *);
static void (WINAPI *gl_DeleteTextures)(GLsizei, const GLuint *);
static void (WINAPI *gl_TexImage2D)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *);
static void (WINAPI *gl_TexParameteri)(GLenum, GLenum, GLint);
static void (WINAPI *gl_DrawArrays)(GLenum, GLint, GLsizei);
static void (WINAPI *gl_ActiveTexture)(GLenum);
static GLuint (WINAPI *gl_CreateShader)(GLenum);
static void (WINAPI *gl_ShaderSource)(GLuint, GLsizei, const GLchar *const *, const GLint *);
static void (WINAPI *gl_CompileShader)(GLuint);
static GLuint (WINAPI *gl_CreateProgram)(void);
static void (WINAPI *gl_AttachShader)(GLuint, GLuint);
static void (WINAPI *gl_LinkProgram)(GLuint);
static void (WINAPI *gl_DeleteShader)(GLuint);
static void (WINAPI *gl_GetProgramiv)(GLuint, GLenum, GLint *);
static void (WINAPI *gl_UseProgram)(GLuint);
static GLint (WINAPI *gl_GetUniformLocation)(GLuint, const GLchar *);
static void (WINAPI *gl_Uniform1i)(GLint, GLint);
static void (WINAPI *gl_Uniform2f)(GLint, float, float);
static void (WINAPI *gl_GenVertexArrays)(GLsizei, GLuint *);
static void (WINAPI *gl_BindVertexArray)(GLuint);
static void (WINAPI *gl_GenBuffers)(GLsizei, GLuint *);
static void (WINAPI *gl_BindBuffer)(GLenum, GLuint);
static void (WINAPI *gl_BufferData)(GLenum, ptrdiff_t, const void *, GLenum);
static void (WINAPI *gl_VertexAttribPointer)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void *);
static void (WINAPI *gl_EnableVertexAttribArray)(GLuint);
static void (WINAPI *gl_BindAttribLocation)(GLuint, GLuint, const GLchar *);
static void (WINAPI *gl_BindFramebuffer)(GLenum, GLuint);

static BOOL g_ready, g_open;
static const ui_item *g_items;
static int g_item_count;
static GLuint g_prog, g_vao, g_vbo, g_font, g_logo;
static GLint g_loc_screen;
static int g_font_px, g_cell, g_advance[FONT_LAST - FONT_FIRST + 1];

static float g_vertices[MAX_QUADS * 6 * VERTEX_FLOATS];
static int g_vertex_count, g_panel_first, g_panel_end;
static GLint g_panel_clip[4];
static void (WINAPI *gl_Scissor)(GLint,GLint,GLsizei,GLsizei);

static HWND g_input_window;
static HCURSOR g_game_cursor;
static BOOL g_mouse_was_down, g_reading_key, g_key_was_down[256];
static int g_dragging = -1;
static float g_slider_pointer_x;


static wchar_t g_packs[MAX_PACKS][64];
static int g_pack_count;

static const char *const g_tab_names[UI_TABS] = { "Look", "Weather", "Quality", "Materials", "Lighting" };
static int g_tab;		/* the page showing, kept while the game runs */
static int g_tab_rows;		/* the longest page, which sets the row height */

static const char *const g_vs =
	"#version 150\n"
	"in vec2 a_pos, a_uv;\n"
	"in vec4 a_color;\n"
	"out vec2 v_uv;\n"
	"out vec4 v_color;\n"
	"uniform vec2 u_screen;\n"
	"void main()\n"
	"{\n"
	"	v_uv = a_uv;\n"
	"	v_color = a_color;\n"
	"	gl_Position = vec4(a_pos / u_screen * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0.0, 1.0);\n"
	"}\n";

/* Text has coordinates in the font, shapes use a negative one for full coverage. */
static const char *const g_fs =
	"#version 150\n"
	"in vec2 v_uv;\n"
	"in vec4 v_color;\n"
	"out vec4 f_color;\n"
	"uniform sampler2D u_font,u_logo;\n"
	"void main()\n"
	"{\n"
	"	if(v_uv.x>=2.0){float l=texture(u_logo,v_uv-vec2(2.0,0.0)).r;f_color=vec4(vec3(l),v_color.a);return;}float a = v_uv.x < 0.0 ? 1.0 : texture(u_font, v_uv).r;\n"
	"	f_color = vec4(v_color.rgb, v_color.a * a);\n"
	"}\n";

#define LOAD(var, name) *(PROC *)&var = get_proc(name)
#define LOAD_GL11(var, name) *(FARPROC *)&var = GetProcAddress(g_real_gl, name)

static GLuint compile(GLenum type, const char *src)
{
	GLuint s = gl_CreateShader(type);

	gl_ShaderSource(s, 1, &src, NULL);
	gl_CompileShader(s);
	return s;
}

void ui_init(PROC (WINAPI *get_proc)(LPCSTR), const ui_item *items, int count)
{
	GLuint vs, fs;
	GLint ok = 0;
	int rows[UI_TABS] = { 0 }, i;
	rows[UI_TAB_LIGHTING]=4; /* Four rows of lighting preset buttons. */
	GLint previous_active_texture, previous_logo_binding;

	g_items = items;
	g_item_count = count;
	for (i = 0; i < count; i++) {
		rows[items[i].tab]++;
		g_tab_rows = max(g_tab_rows, rows[items[i].tab]);
	}

	LOAD_GL11(gl_Enable, "glEnable");
	LOAD_GL11(gl_Disable, "glDisable");
	LOAD_GL11(gl_IsEnabled, "glIsEnabled");
	LOAD_GL11(gl_GetIntegerv, "glGetIntegerv");
	LOAD_GL11(gl_BlendFunc, "glBlendFunc");
	LOAD_GL11(gl_Viewport, "glViewport");
	LOAD_GL11(gl_Scissor, "glScissor");
	LOAD_GL11(gl_BindTexture, "glBindTexture");
	LOAD_GL11(gl_GenTextures, "glGenTextures");
	LOAD_GL11(gl_DeleteTextures, "glDeleteTextures");
	LOAD_GL11(gl_TexImage2D, "glTexImage2D");
	LOAD_GL11(gl_TexParameteri, "glTexParameteri");
	LOAD_GL11(gl_DrawArrays, "glDrawArrays");

	LOAD(gl_ActiveTexture, "glActiveTexture");
	LOAD(gl_CreateShader, "glCreateShader");
	LOAD(gl_ShaderSource, "glShaderSource");
	LOAD(gl_CompileShader, "glCompileShader");
	LOAD(gl_CreateProgram, "glCreateProgram");
	LOAD(gl_AttachShader, "glAttachShader");
	LOAD(gl_LinkProgram, "glLinkProgram");
	LOAD(gl_DeleteShader, "glDeleteShader");
	LOAD(gl_GetProgramiv, "glGetProgramiv");
	LOAD(gl_UseProgram, "glUseProgram");
	LOAD(gl_GetUniformLocation, "glGetUniformLocation");
	LOAD(gl_Uniform1i, "glUniform1i");
	LOAD(gl_Uniform2f, "glUniform2f");
	LOAD(gl_GenVertexArrays, "glGenVertexArrays");
	LOAD(gl_BindVertexArray, "glBindVertexArray");
	LOAD(gl_GenBuffers, "glGenBuffers");
	LOAD(gl_BindBuffer, "glBindBuffer");
	LOAD(gl_BufferData, "glBufferData");
	LOAD(gl_VertexAttribPointer, "glVertexAttribPointer");
	LOAD(gl_EnableVertexAttribArray, "glEnableVertexAttribArray");
	LOAD(gl_BindAttribLocation, "glBindAttribLocation");
	LOAD(gl_BindFramebuffer, "glBindFramebuffer");

	vs = compile(GL_VERTEX_SHADER, g_vs);
	fs = compile(GL_FRAGMENT_SHADER, g_fs);
	g_prog = gl_CreateProgram();
	gl_AttachShader(g_prog, vs);
	gl_AttachShader(g_prog, fs);
	gl_BindAttribLocation(g_prog, 0, "a_pos");
	gl_BindAttribLocation(g_prog, 1, "a_uv");
	gl_BindAttribLocation(g_prog, 2, "a_color");
	gl_LinkProgram(g_prog);
	gl_DeleteShader(vs);
	gl_DeleteShader(fs);
	gl_GetProgramiv(g_prog, GL_LINK_STATUS, &ok);
	if (!ok) {
		log_msg("ui: shaders failed to link, no settings panel");
		return;
	}
	gl_UseProgram(g_prog);
	gl_Uniform1i(gl_GetUniformLocation(g_prog, "u_font"), UNIT_FONT);
    gl_Uniform1i(gl_GetUniformLocation(g_prog,"u_logo"),19);
    /* Asset upload must not change the game's active texture slot or binding. */
    gl_GetIntegerv(0x84E0 /* GL_ACTIVE_TEXTURE */,&previous_active_texture);
    gl_GenTextures(1,&g_logo);gl_ActiveTexture(GL_TEXTURE0+19);
    gl_GetIntegerv(0x8069 /* GL_TEXTURE_BINDING_2D */,&previous_logo_binding);
    gl_BindTexture(GL_TEXTURE_2D,g_logo);
    gl_TexParameteri(GL_TEXTURE_2D,0x2802,0x812F);
    gl_TexParameteri(GL_TEXTURE_2D,0x2803,0x812F);
    void (WINAPI *generate_mipmap)(GLenum);
    LOAD(generate_mipmap,"glGenerateMipmap");
    void (WINAPI *pixel_store)(GLenum,GLint);
    LOAD_GL11(pixel_store,"glPixelStorei");
    GLint unpack_alignment;
    gl_GetIntegerv(0x0CF5,&unpack_alignment);
    pixel_store(0x0CF5,1);
    gl_TexImage2D(GL_TEXTURE_2D,0,0x8229,FLICKS_LOGO_W,FLICKS_LOGO_H,0,0x1903,GL_UNSIGNED_BYTE,flicks_logo);
    pixel_store(0x0CF5,unpack_alignment);
    if(generate_mipmap)generate_mipmap(GL_TEXTURE_2D);
    gl_TexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,generate_mipmap?0x2703:GL_LINEAR);
    gl_TexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    gl_BindTexture(GL_TEXTURE_2D,(GLuint)previous_logo_binding);
    gl_ActiveTexture((GLenum)previous_active_texture);
	g_loc_screen = gl_GetUniformLocation(g_prog, "u_screen");
	gl_UseProgram(0);

	gl_GenVertexArrays(1, &g_vao);
	gl_GenBuffers(1, &g_vbo);
	g_font = 0;
	g_font_px = 0;
	g_ready = TRUE;
}

void ui_context_lost(void)
{
	g_ready = FALSE;
}

BOOL ui_is_open(void)
{
	return g_open;
}

BOOL ui_is_reading_key(void)
{
	return g_reading_key;
}

/* --- the font --- */

/* Verdana Bold Italic is close to the game's menu font and comes with Windows. */
static void font_build(int px)
{
	BITMAPINFO bmi = { 0 };
	unsigned char *pixels = NULL;
	int raster_px=px*2;
	int cell = raster_px * 2, w = FONT_COLUMNS * cell, h = FONT_ROWS * cell, c, i;
	HDC dc = CreateCompatibleDC(NULL);
	HBITMAP bitmap;
	HFONT font;
	HGDIOBJ previous_font,previous_bitmap;

	bmi.bmiHeader.biSize = sizeof bmi.bmiHeader;
	bmi.bmiHeader.biWidth = w;
	bmi.bmiHeader.biHeight = -h;
	bmi.bmiHeader.biPlanes = 1;
	bmi.bmiHeader.biBitCount = 32;
	bmi.bmiHeader.biCompression = BI_RGB;
	bitmap = CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, (void **)&pixels, NULL, 0);
	font = CreateFontW(-raster_px, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
			   CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Segoe UI");
	if (!bitmap || !font || !pixels) {
		log_msg("ui: font failed");
		DeleteDC(dc);
		return;
	}
	memset(pixels,0,(size_t)w*h*4);
	previous_bitmap=SelectObject(dc, bitmap);
	previous_font=SelectObject(dc, font);
	SetBkMode(dc, TRANSPARENT);
	SetTextColor(dc, RGB(255, 255, 255));
	for (c = FONT_FIRST; c <= FONT_LAST; c++) {
		char ch = (char)c;
		SIZE size;

		i = c - FONT_FIRST;
		GetTextExtentPoint32A(dc, &ch, 1, &size);
		g_advance[i] = (size.cx+1)/2;
		TextOutA(dc, i % FONT_COLUMNS * cell + raster_px / 4, i / FONT_COLUMNS * cell, &ch, 1);
	}

	if (!g_font)
		gl_GenTextures(1, &g_font);
	gl_ActiveTexture(GL_TEXTURE0 + UNIT_FONT);
	gl_BindTexture(GL_TEXTURE_2D, g_font);
	gl_TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_BGRA, GL_UNSIGNED_BYTE, pixels);
	gl_TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	gl_TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

	SelectObject(dc,previous_font);SelectObject(dc,previous_bitmap);
	DeleteObject(font);
	DeleteObject(bitmap);
	DeleteDC(dc);
	g_font_px = px;
	g_cell = cell/2;
}

/* --- drawing --- */

static void vertex(float x, float y, float u, float v, color c)
{
	float *f = &g_vertices[g_vertex_count++ * VERTEX_FLOATS];

	f[0] = x;
	f[1] = y;
	f[2] = u;
	f[3] = v;
	f[4] = c.r;
	f[5] = c.g;
	f[6] = c.b;
	f[7] = c.a;
}

static void quad_uv(float x0, float y0, float x1, float y1, float u0, float v0, float u1, float v1, color c)
{
	if (g_vertex_count + 6 > MAX_QUADS * 6)
		return;
	vertex(x0, y0, u0, v0, c);
	vertex(x1, y0, u1, v0, c);
	vertex(x1, y1, u1, v1, c);
	vertex(x0, y0, u0, v0, c);
	vertex(x1, y1, u1, v1, c);
	vertex(x0, y1, u0, v1, c);
}

static void fill(float x, float y, float w, float h, color c)
{
	quad_uv(x, y, x + w, y + h, -1.0f, 0.0f, -1.0f, 0.0f, c);
}

static void box(float x, float y, float w, float h, color back, color edge)
{
	const float t = 1.0f;

	fill(x, y, w, h, back);
	fill(x, y, w, t, edge);
	fill(x, y + h - t, w, t, edge);
	fill(x, y + t, t, h - 2 * t, edge);
	fill(x + w - t, y + t, t, h - 2 * t, edge);
}

static void label_box(float x, float y, float w, float h)
{
	box(x, y, w, h, LABEL_BOX, LABEL_EDGE);
}

/* Buttons and values, white under the mouse like the game's menus. */
static void button_box(float x, float y, float w, float h, BOOL selected)
{
	box(x, y, w, h, selected ? SELECTED : BUTTON_BOX, selected ? SELECTED_EDGE : BUTTON_EDGE);
}

/* The menus space their letters out. */
static float spacing(void)
{
	return g_font_px * 0.015f;
}

static float text_width(const char *s)
{
	float w = 0.0f;

	for (; *s; s++)
		if (*s >= FONT_FIRST && *s <= FONT_LAST)
			w += g_advance[*s - FONT_FIRST] + spacing();
	return w;
}

static void glyphs(float x, float y, const char *s, color c)
{
	const float tw = 1.0f / FONT_COLUMNS, th = 1.0f / FONT_ROWS;

	for (; *s; s++) {
		int i;
		float u, v;

		if (*s < FONT_FIRST || *s > FONT_LAST)
			continue;
		i = *s - FONT_FIRST;
		u = (i % FONT_COLUMNS) * tw;
		v = (i / FONT_COLUMNS) * th;
		quad_uv(x - g_font_px * 0.25f, y, x - g_font_px * 0.25f + g_cell, y + g_cell, u, v, u + tw, v + th, c);
		x += g_advance[i] + spacing();
	}
}

static void text(float x, float y, float h, const char *s, color c)
{
	float top = y + (h - g_font_px * 1.25f) * 0.5f;

	if (c.r > 0.5f)
		glyphs(x + 1.5f, top + 1.5f, s, SHADOW);
	glyphs(x, top, s, c);
}

/* --- the input window --- */

static LRESULT CALLBACK input_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
	switch (msg) {
	case WM_MOUSEACTIVATE:
		return MA_NOACTIVATE;
	case WM_SETCURSOR:
		SetCursor(g_game_cursor);
		return TRUE;
	}
	return DefWindowProcW(hwnd, msg, wp, lp);
}

static void input_window_open(HWND game)
{
	static BOOL registered;
	POINT origin = { 0, 0 };
	RECT r;

	if (!registered) {
		WNDCLASSW wc = { 0 };

		wc.lpfnWndProc = input_proc;
		wc.hInstance = GetModuleHandleW(NULL);
		wc.lpszClassName = L"MXSShadersInput";
		RegisterClassW(&wc);
		registered = TRUE;
	}
	g_game_cursor = (HCURSOR)GetClassLongPtrW(game, GCLP_HCURSOR);
	GetClientRect(game, &r);
	ClientToScreen(game, &origin);
	g_input_window = CreateWindowExW(WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, L"MXSShadersInput", L"", WS_POPUP,
					 origin.x, origin.y, r.right, r.bottom, game, NULL, GetModuleHandleW(NULL), NULL);
	if (!g_input_window) {
		log_msg("ui: no input window (%lu), clicks will reach the game", GetLastError());
		return;
	}
	/* The lowest alpha that still receives the mouse, invisible but solid. */
	SetLayeredWindowAttributes(g_input_window, 0, 1, LWA_ALPHA);
	ShowWindow(g_input_window, SW_SHOWNOACTIVATE);
}

static void input_window_close(void)
{
	if (g_input_window)
		DestroyWindow(g_input_window);
	g_input_window = NULL;
}

static void packs_scan(void)
{
	wchar_t pattern[MAX_PATH];
	WIN32_FIND_DATAW fd;
	HANDLE h;

	wcscpy_s(g_packs[0], 64, L"default");
	g_pack_count = 1;
	log_path(pattern, L"shaderpacks\\*");
	h = FindFirstFileW(pattern, &fd);
	if (h == INVALID_HANDLE_VALUE)
		return;
	do {
		if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || fd.cFileName[0] == L'.' ||
		    !wcscmp(fd.cFileName, L"default") || wcslen(fd.cFileName) >= 64 || g_pack_count == MAX_PACKS)
			continue;
		wcscpy_s(g_packs[g_pack_count++], 64, fd.cFileName);
	} while (FindNextFileW(h, &fd));
	FindClose(h);
}

void ui_toggle(HWND game)
{
	if (!g_ready)
		return;
	g_open = !g_open;
	g_dragging = -1;
	g_reading_key = FALSE;
	g_mouse_was_down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
	if (g_open) {
		packs_scan();
		input_window_open(game);
	} else {
		input_window_close();
	}
}

/* --- the panel --- */

static BOOL inside(float px, float py, float x, float y, float w, float h)
{
	return px >= x && px < x + w && py >= y && py < y + h;
}

static int choice_index(const ui_item *it)
{
	int i;

	for (i = 0; i < it->choice_count; i++)
		if (it->choices[i] == *it->value)
			return i;
	return 0;
}


static void slider_set(const ui_item *it, float t)
{
	t=min(max(t,0.0f),1.0f);
	int v = it->min + (int)((it->max - it->min) * t / it->step + 0.5f) * it->step;

	*it->value = min(max(v, it->min), it->max);
}

static void pack_row(float x, float y, float label_w, float value_w, float row, float mx, float my, BOOL click, const wchar_t *pack)
{
	char name[64];
	BOOL hover = inside(mx, my, x, y, label_w + value_w, row);
	int i, current = 0;

	for (i = 0; i < g_pack_count; i++)
		if (!_wcsicmp(g_packs[i], pack))
			current = i;
	WideCharToMultiByte(CP_ACP, 0, g_packs[current], -1, name, sizeof name, NULL, NULL);

	label_box(x, y, label_w, row);
	text(x + row * 0.2f, y, row, "Shader Pack", TEXT_LIGHT);
	button_box(x + label_w, y, value_w, row, hover);
	text(x + label_w + row * 0.2f, y, row, name, hover ? TEXT_DARK : TEXT_LIGHT);

	if (hover && click && g_pack_count > 1)
		ui_pack_changed(g_packs[(current + 1) % g_pack_count]);
}

static int g_hover_setting=-1;
static const char *g_hover_preset_help;
static const char *setting_help(const wchar_t *key)
{
    static const struct {const wchar_t *key;const char *help;} help[]={
        {L"bike_materials","Adds material shading to bike plastics, metal and rider gear."},
        {L"actor_dirt","Builds soil-colored dirt on the tires, bike and front of the rider."},
        {L"actor_dirt_amount","Sets the amount of dirt on bike and gear materials and on tires."},
        {L"roost","Toggles the dust and mud thrown behind the rear wheel."},
        {L"roost_amount","Changes the size and visibility of dust and mud."},
        {L"material_light","Changes the brightness of material highlights."},
        {L"ambient_light","Adjusts the fill light in areas without direct sun."},
        {L"tire_tracks","Shades separate front and rear tire grooves on the track surface."},
        {L"motion_enabled","Blurs passing scenery while the nearby rider and bike stay sharp."},
        {L"motion_strength","Higher strength stretches moving scenery more."},
        {L"motion_max_length","Limits the length of motion blur streaks."},
        {L"motion_fallback_radius","Extends chase-camera protection. Zero uses JSC500's automatic first-person and chase cutoffs."},
        {L"motion_samples","Higher quality uses more samples for smoother streaks."},
        {L"shadow_darkness","Darkens shadows cast by the sun onto riders and the track."},
        {L"contact_strength","Adjusts small shadows where objects nearly touch."},
        {L"ao_strength","Darkens corners and creases where ambient light is blocked."},
        {L"ao_samples","More samples can smooth ambient shadows at an FPS cost."},
        {L"ao_quality","Controls the resolution of ambient occlusion."},
        {L"fog","Changes the amount of haze over distant scenery."},
        {L"dof","Controls the strength of the standard depth of field. Zero turns it off."},
        {L"saturation","Changes how vivid the colors look."},
        {L"contrast","Changes the separation between dark and bright tones."},
        {L"split_tone","Tints shadows cooler and highlights warmer."},
        {L"texture_sharpness","Makes texture detail sharper and can increase shimmer."},
        {L"bloom","Adds a soft glow around bright areas."},
        {L"shadow_debug","Shows the scene or rider shadow sampled on visible surfaces. Magenta means the selected map is unavailable."},
        {L"weather","Chooses clear skies, clouds, rain, storm or snow."},
        {L"weather_amount","Changes the intensity of the selected weather."},
        {L"wet","Changes how wet and reflective the ground looks."},
        {L"sun_height","Changes the sun's elevation. Zero uses the track's sun."},
        {L"sun_turn","Rotates the sun's direction around the track."},
        {L"noise_reduction","Softens fine visual noise. Zero turns it off."},
        {L"edge_smoothing","Softens jagged edges in the finished scene."},
        {L"hide_hud","Hides the game's race HUD."},
        {L"hide_cursor","Hides the mouse pointer while riding."},
        {L"shadow_riders","Limits moving rider shadows. Higher limits can cost FPS."},
        {L"shadow_size","Changes shadow map resolution. Restart to apply."},
        {L"msaa","Smooths geometry edges. Higher values cost FPS. Restart to apply."},
        {L"anisotropy","Keeps angled textures clearer. Restart to apply."},
        {L"borderless","Makes windowed mode fill the display. Restart to apply."}
    };
    for(unsigned i=0;i<sizeof help/sizeof help[0];i++)
        if(!wcscmp(key,help[i].key))return help[i].help;
    return NULL;
}

static void item_row(int index, float x, float y, float label_w, float value_w, float row, float mx, float my, BOOL down, BOOL click)
{
	const ui_item *it = &g_items[index];
	BOOL hover = inside(mx, my, x, y, label_w + value_w, row);
	BOOL active = g_dragging == index || (hover && g_dragging < 0);
	char value[32];
    if(hover&&!down)g_hover_setting=index;

	label_box(x, y, label_w, row);
	text(x + row * 0.2f, y, row, it->label, TEXT_LIGHT);
	if (it->restart)
		text(x + row * 0.2f + text_width(it->label), y, row, "*", ASTERISK);

	if (it->kind == UI_SLIDER) {
		float number_w = row * 2.4f, bar_x = x + label_w + number_w, bar_w = value_w - number_w;
		float t = (float)(*it->value - it->min) / (it->max - it->min);
		if (hover && click)
			g_dragging = index;
		if (g_dragging == index) {
			if (down) {
                slider_set(it, (g_slider_pointer_x - bar_x) / max(1.0f,bar_w));
            }
			else {
				g_dragging = -1;
				ui_setting_changed(it);
			}
		}

		label_box(x + label_w, y, number_w, row);

        if(!wcscmp(it->key,L"motion_strength"))
            sprintf_s(value,sizeof value,"%.2f",*it->value/100.0);
        else if(!wcscmp(it->key,L"motion_max_length")||!wcscmp(it->key,L"motion_fallback_radius"))
            sprintf_s(value,sizeof value,"%.1f",*it->value/10.0);
        else sprintf_s(value,sizeof value,"%d",*it->value);
        text(x + label_w + number_w - text_width(value) - row * 0.2f, y, row, value, TEXT_LIGHT);

		button_box(bar_x, y, bar_w, row, active);
		fill(bar_x + row * 0.12f, y + row * 0.46f, (bar_w - row * 0.24f) * min(max(t, 0.0f), 1.0f), 3.0f, active ? TEXT_DARK : BAR);
		return;
	}

	if (it->kind == UI_TOGGLE)
		strcpy_s(value, sizeof value, *it->value ? "ON" : "OFF");
	else if (it->names)
		strcpy_s(value, sizeof value, it->names[choice_index(it)]);
	else
		sprintf_s(value, sizeof value, "%d", *it->value);
	button_box(x + label_w, y, value_w, row, active);
	text(x + label_w + row * 0.2f, y, row, value, active ? TEXT_DARK : TEXT_LIGHT);

	if (hover && click) {
		if (it->kind == UI_TOGGLE)
			*it->value = !*it->value;
		else
			*it->value = it->choices[(choice_index(it) + 1) % it->choice_count];
		ui_setting_changed(it);
	}
}

/* The pages across the panel, the one showing lit like a selected menu row. */
static void tab_row(float x, float y, float w, float row, float gap, float mx, float my, BOOL click)
{
	float tab_w = (w - gap * (UI_TABS - 1)) / UI_TABS;
	int t;

	for (t = 0; t < UI_TABS; t++) {
		float tx = x + t * (tab_w + gap);
		BOOL lit = t == g_tab || inside(mx, my, tx, y, tab_w, row);

		button_box(tx, y, tab_w, row, lit);
		text(tx + (tab_w - text_width(g_tab_names[t])) * 0.5f, y, row, g_tab_names[t], lit ? TEXT_DARK : TEXT_LIGHT);
		if (lit && click)
			g_tab = t;
	}
}

/* The first key to go down since the last call, not counting the mouse buttons. */
static int key_pressed(void)
{
	int vk, pressed = 0;

	for (vk = VK_BACK; vk < 256; vk++) {
		BOOL down = (GetAsyncKeyState(vk) & 0x8000) != 0;

		if (down && !g_key_was_down[vk] && !pressed)
			pressed = vk;
		g_key_was_down[vk] = down;
	}
	return pressed;
}

/* Names come from the keyboard layout. The font skips what it doesn't have, such as umlauts. */
static void key_name(int vk, char *name, int size)
{
	UINT code = MapVirtualKeyA(vk, MAPVK_VK_TO_VSC_EX);
	LONG lp = (code & 0xff) << 16 | ((code & 0xff00) ? 1 << 24 : 0);

	if (!GetKeyNameTextA(lp, name, size))
		sprintf_s(name, size, "Key %d", vk);
}

/* 205 Flicks monochrome panel. Uses the existing input capture and setting API. */
static void small_text(float x,float y,float h,const char *label,color c,float scale)
{
    int first=g_vertex_count,i;
    text(x,y,h,label,c);
    for(i=first;i<g_vertex_count;i++){
        float *v=&g_vertices[i*VERTEX_FLOATS];v[0]=x+(v[0]-x)*scale;v[1]=y+(v[1]-y)*scale;
    }
}
static int menu_tip_index=-1;
static DWORD menu_tip_since;

static void menu_tooltip(float mx,float my,float width,float height)
{
    DWORD now=GetTickCount();
    if(g_hover_setting!=menu_tip_index){
        menu_tip_index=g_hover_setting;
        menu_tip_since=now;
    }
    if(menu_tip_index<0||now-menu_tip_since<400)return;
    const char *help=g_hover_preset_help?g_hover_preset_help:setting_help(g_items[menu_tip_index].key);
    if(!help)return;
    float tw=min(390.0f,width-8),x=max(4.0f,min(mx+15,width-tw-4));
    char lines[5][100]={{0}};
    int count=0;
    while(*help&&count<5){
        int used=0;
        while(*help){
            const char *end=help;
            while(*end&&*end!=' ')end++;
            int len=(int)(end-help);
            if(used+len+1>=100)break;
            int previous=used;
            if(used)lines[count][used++]=' ';
            memcpy(lines[count]+used,help,len);lines[count][used+len]=0;
            if(previous && text_width(lines[count])>tw-20){lines[count][previous]=0;break;}
            used+=len;help=*end?end+1:end;
        }
        count++;
    }
    float th=12+count*23.0f,y=my+19;
    if(y+th>height-4)y=max(4.0f,my-th-8);
    box(x,y,tw,th,(color){0.075f,0.075f,0.075f,1},(color){0.41f,0.41f,0.41f,1});
    for(int i=0;i<count;i++)small_text(x+10,y+5+i*23,23,lines[i],TEXT_LIGHT,0.90f);
}

static int panel_width, panel_height, resize_edges, scroll_axis;
static int panel_offset_x,panel_offset_y;
static BOOL panel_moving;
static POINT panel_move_grab;
static float panel_scroll_x,panel_scroll_y,scroll_grab;
static RECT resize_start;
static POINT resize_mouse;

static void scrollbar(float x,float y,float length,float visible,float full,float *offset,
                      float mx,float my,BOOL down,BOOL click,int axis)
{
    float thumb=max(24.0f,length*visible/full);
    float travel=max(1.0f,length-thumb);
    float start=travel*(*offset)/max(1.0f,full-visible);
    float at=axis==1?mx-x:my-y;
    BOOL hover=inside(mx,my,x,y,axis==1?length:12,axis==1?12:length);
    if(click&&hover){
        scroll_axis=axis;
        scroll_grab=at>=start&&at<=start+thumb?at-start:thumb*0.5f;
    }
    if(down&&scroll_axis==axis){
        start=max(0.0f,min(travel,at-scroll_grab));
        *offset=start/travel*(full-visible);
    }
    fill(x,y,axis==1?length:12,axis==1?12:length,(color){0.09f,0.09f,0.09f,1});
    fill(x+(axis==1?start:2),y+(axis==1?2:start),axis==1?thumb:8,axis==1?8:thumb,
         (color){0.55f,0.55f,0.55f,1});
}

static void panel(HWND game,int w,int h,const wchar_t *pack,const ui_state *s)
{
    float pw=min(w*0.94f,1160.0f),ph=min(h*0.94f,950.0f);
    float x=(w-pw)*0.5f,y=(h-ph)*0.5f,pad=max(14.0f,pw*0.022f);
    float side=pw*0.205f,main_x=x+side+pad,main_w=pw-side-pad*2;
    float head=ph*0.16f,row=min(44.0f,(ph-head-170.0f)/g_tab_rows-3.0f);
    float content_y=y+head+52.0f,label_w=main_w*0.47f,value_w=main_w-label_w;
    float mx,my;BOOL down=(GetAsyncKeyState(VK_LBUTTON)&0x8000)!=0,click=down&&!g_mouse_was_down;
    POINT p;int i,t,order[UI_TABS]={UI_TAB_LOOK,UI_TAB_MATERIALS,UI_TAB_LIGHTING,UI_TAB_WEATHER,UI_TAB_DISPLAY};
    const color panel_bg={0.035f,0.035f,0.035f,0.985f},muted={0.52f,0.52f,0.52f,1},line={0.16f,0.16f,0.16f,1};
    const char *description="Color, atmosphere and camera effects.";
    (void)pack;
    GetCursorPos(&p);ScreenToClient(game,&p);mx=(float)p.x;my=(float)p.y;
#ifdef FLICKS_PREVIEW_UI
    down=click=FALSE;mx=my=-100;
#endif
    g_mouse_was_down=down;
    g_hover_setting=-1;
    g_hover_preset_help=NULL;
    float pointer_x=mx,pointer_y=my;
    float vw=min((float)w,panel_width?min(panel_width,pw):pw);
    float vh=min((float)h,panel_height?min(panel_height,ph):ph);
    float vx=max(0.0f,min(w-vw,x+panel_offset_x));
    float vy=max(0.0f,min(h-vh,y+panel_offset_y));
    if(!down){resize_edges=0;scroll_axis=0;panel_moving=FALSE;}
    if(click&&inside(mx,my,vx,vy,vw,vh)){
        resize_edges=(mx<vx+6?1:mx>=vx+vw-6?2:0)|(my<vy+6?4:my>=vy+vh-6?8:0);
        if(resize_edges){
            resize_start=(RECT){(LONG)vx,(LONG)vy,(LONG)(vx+vw),(LONG)(vy+vh)};
            resize_mouse=p;
        }
    }
    BOOL center_hover=inside(mx,my,vx+vw-78,vy+47,66,24);
    if(click&&center_hover&&!resize_edges){
        vx=(w-vw)*0.5f;vy=(h-vh)*0.5f;
        panel_offset_x=(int)(vx-x);panel_offset_y=(int)(vy-y);
        click=FALSE;
    }
    if(click && !resize_edges && !scroll_axis &&
       inside(mx,my,vx,vy,vw,min(vh,head)) &&
       !inside(mx+x-vx+panel_scroll_x,my+y-vy+panel_scroll_y,x+pw-42,y+8,34,32)){
        panel_moving=TRUE;
        panel_move_grab=(POINT){p.x-(LONG)vx,p.y-(LONG)vy};
    }
    if(panel_moving){
        vx=max(0.0f,min(w-vw,(float)(p.x-panel_move_grab.x)));
        vy=max(0.0f,min(h-vh,(float)(p.y-panel_move_grab.y)));
        panel_offset_x=(int)(vx-x);panel_offset_y=(int)(vy-y);
        click=FALSE;
    }
    if(resize_edges){
        RECT edge=resize_start;
        if(resize_edges&1)edge.left=max(0,min(edge.right-160,max(edge.right-(LONG)pw,edge.left+p.x-resize_mouse.x)));
        if(resize_edges&2)edge.right=max(edge.left+160,min(min(w,edge.left+(LONG)pw),edge.right+p.x-resize_mouse.x));
        if(resize_edges&4)edge.top=max(0,min(edge.bottom-130,max(edge.bottom-(LONG)ph,edge.top+p.y-resize_mouse.y)));
        if(resize_edges&8)edge.bottom=max(edge.top+130,min(min(h,edge.top+(LONG)ph),edge.bottom+p.y-resize_mouse.y));
        vx=edge.left;vy=edge.top;vw=edge.right-edge.left;vh=edge.bottom-edge.top;
        panel_offset_x=(int)(vx-x);panel_offset_y=(int)(vy-y);
        panel_width=(int)vw;panel_height=(int)vh;
        click=FALSE;
    }
    float cw=vw,ch=vh;
    if(ph>ch)cw-=12;
    if(pw>cw)ch-=12;
    if(ph>ch&&cw==vw)cw-=12;
    panel_scroll_x=max(0.0f,min(panel_scroll_x,pw-cw));
    panel_scroll_y=max(0.0f,min(panel_scroll_y,ph-ch));
    box(vx,vy,vw,vh,panel_bg,line);
    if(pw>cw)scrollbar(vx,vy+ch,cw,cw,pw,&panel_scroll_x,mx,my,down,click,1);
    if(ph>ch)scrollbar(vx+cw,vy,ch,ch,ph,&panel_scroll_y,mx,my,down,click,2);
    if(panel_moving||resize_edges||scroll_axis||!inside(mx,my,vx,vy,cw,ch)){mx=my=-10000;click=FALSE;}
    else {mx+=x-vx+panel_scroll_x;my+=y-vy+panel_scroll_y;}
    g_slider_pointer_x=pointer_x+x-vx+panel_scroll_x;
    g_panel_first=g_vertex_count;
    g_panel_clip[0]=(GLint)vx;g_panel_clip[1]=(GLint)(h-vy-ch);
    g_panel_clip[2]=(GLint)cw;g_panel_clip[3]=(GLint)ch;

    fill(x+side,y+head,1,ph-head,line);
    fill(x+pad,y+head-1,pw-pad*2,1,line);
    /* Original supplied logo on its own white card. UV > 2 selects the logo texture. */
    fill(x+pad,y+pad,side-pad*2,head-pad*2,(color){1,1,1,1});
    {
        float available_w=side-pad*2-10,available_h=head-pad*2-10;
        float scale=min(available_w/FLICKS_LOGO_W,available_h/FLICKS_LOGO_H);
        float lw=FLICKS_LOGO_W*scale,lh=FLICKS_LOGO_H*scale;
        float lx=x+(side-lw)*0.5f,ly=y+(head-lh)*0.5f;
        quad_uv(lx,ly,lx+lw,ly+lh,2,0,3,1,(color){1,1,1,1});
    }
    small_text(main_x,y+head*0.30f,34,"Private 205 Flicks MXS Shaders Mod",TEXT_LIGHT,1.15f);
    small_text(main_x,y+head*0.78f,22,"NATIVE GRAPHICS",muted,0.72f);
    /* A compact close control, independent of the game's menu styling. */
    if(inside(mx,my,x+pw-42,y+8,34,32)){
        button_box(x+pw-42,y+8,34,32,TRUE);if(click)ui_toggle(game);
    }
    text(x+pw-33,y+8,32,"X",inside(mx,my,x+pw-42,y+8,34,32)?TEXT_DARK:TEXT_LIGHT);
    for(i=0;i<UI_TABS;i++){
        float ny=y+head+24+i*51.0f,nh=42.0f;
        BOOL hover; t=order[i];hover=inside(mx,my,x+pad,ny,side-pad*2,nh);
        if(t==g_tab){fill(x+pad,ny,side-pad*2,nh,(color){0.94f,0.94f,0.94f,1});fill(x,ny,3,nh,TEXT_LIGHT);}
        else if(hover)fill(x+pad,ny,side-pad*2,nh,(color){0.13f,0.13f,0.13f,1});
        text(x+pad+12,ny,nh,g_tab_names[t],t==g_tab?TEXT_DARK:TEXT_LIGHT);
        if(hover&&click){g_tab=t;g_dragging=-1;}
    }
    if(g_tab==UI_TAB_MATERIALS)description="Rough soil, controlled sheen and richer material highlights.";
    if(g_tab==UI_TAB_LIGHTING)description="Choose a lighting preset for the track and sky.";
    if(g_tab==UI_TAB_WEATHER)description="Sun direction, time of day and surface weather.";
    if(g_tab==UI_TAB_DISPLAY){
        description="Anti-aliasing, shadows, textures and display.";
        row=min(row,(ph-head-249.0f)/9.0f-3.0f);
    }
    text(main_x,y+head+12,32,g_tab_names[g_tab],TEXT_LIGHT);
    small_text(main_x,content_y-14,24,description,muted,0.72f);
    content_y+=20;
    if(g_tab==UI_TAB_LIGHTING){
        static const char *names[]={"Track Default","Morning","Midday","Sunset","Moonlit Night","Day Stadium Race","Night Stadium Race"};
        static const int looks[]={0,5,2,4,6,9,10};
        static const char *help[]={
            "Restores the track's default lighting. Good for all kinds of tracks.",
            "Best outdoors. Low morning sunlight with cool shadows and warm highlights.",
            "Best outdoors. High sunlight with a subtle, balanced grade.",
            "Best outdoors. Low golden sunlight and warmer midtones.",
            "Best outdoors. One moonlight casts directional shadows beneath a dark, starry sky.",
            "Best in stadiums. Warm, angled sunlight and a bright daytime sky through openings.",
            "Best in stadiums. Side floodlights bring out the track. Stars are visible through openings."
        };
        float bw=(main_w-8)/2;
        for(i=0;i<7;i++){
            float bx=main_x+(i%2)*(bw+8),by=content_y+(i/2)*(row+3);
            BOOL hover=inside(mx,my,bx,by,bw,row);
            if(hover&&!down){
                g_hover_setting=g_item_count+i;
                g_hover_preset_help=help[i];
            }
            button_box(bx,by,bw,row,hover);
            text(bx+12,by,row,names[i],hover?TEXT_DARK:TEXT_LIGHT);
            if(hover&&click)ui_lighting_preset(looks[i]);
        }
        content_y+=4*(row+3);
    }
    for(i=0;i<g_item_count;i++)if(g_items[i].tab==g_tab){
        item_row(i,main_x,content_y,label_w,value_w,row,mx,my,down,click);
        content_y+=row+3;
    }
    for(int k=0;k<2;k++){
        float by=y+ph-194+k*37.0f,bw=side-pad*2;
        BOOL hover=inside(mx,my,x+pad,by,bw,32);
        button_box(x+pad,by,bw,32,hover);
        small_text(x+pad+8,by,32,k?"LOAD PRESET":"EXPORT PRESET",hover?TEXT_DARK:TEXT_LIGHT,0.73f);
        if(hover&&click)ui_graphics_file(game,!k);
    }
    /* Sidebar actions are stable across every page. */
    {
        float by=y+ph-114,bw=side-pad*2;BOOL hover=inside(mx,my,x+pad,by,bw,34);
        button_box(x+pad,by,bw,34,hover);
        small_text(x+pad+10,by,34,s->enabled?"EFFECTS ON":"EFFECTS OFF",hover?TEXT_DARK:TEXT_LIGHT,0.82f);
        if(hover&&click)ui_enabled_changed(!s->enabled);
        by+=45;hover=inside(mx,my,x+pad,by,bw,34);button_box(x+pad,by,bw,34,hover);
        small_text(x+pad+10,by,34,"BACK TO GAME",hover?TEXT_DARK:TEXT_LIGHT,0.82f);
        if(hover&&click)ui_toggle(game);
    }
    {
        float fy=y+ph-76,bw=(main_w-16)/3;const char *names[3]={"PERFORMANCE","BALANCED","ULTRA"};const int levels[3]={2,0,1};
        fill(main_x,fy-15,main_w,1,line);
        for(i=0;i<3;i++){
            float bx=main_x+i*(bw+8);BOOL hover=inside(mx,my,bx,fy,bw,30);
            button_box(bx,fy,bw,30,hover);small_text(bx+12,fy,30,names[i],hover?TEXT_DARK:TEXT_LIGHT,0.78f);
            if(hover&&click)ui_quality_preset(levels[i]);
        }
        small_text(main_x,fy+38,22,"* MSAA and shadow map sizes require a restart.  F8 closes this panel.",muted,0.67f);
    }
    g_panel_end=g_vertex_count;
    for(i=g_panel_first;i<g_panel_end;i++){
        float *v=&g_vertices[i*VERTEX_FLOATS];
        v[0]+=vx-x-panel_scroll_x;
        v[1]+=vy-y-panel_scroll_y;
    }
    button_box(vx+vw-78,vy+47,66,24,center_hover);
    small_text(vx+vw-69,vy+47,24,"Center",center_hover?TEXT_DARK:TEXT_LIGHT,0.8f);
    menu_tooltip(pointer_x,pointer_y,(float)w,(float)h);
}

void ui_draw(HWND game, int w, int h, const wchar_t *pack, const ui_state *s)
{
	GLboolean blend, depth, cull, scissor, coverage;
	GLint old_scissor[4];
	int px = max(11,min(19,h/54));

	if (!g_ready || !g_open || w <= 0 || h <= 0)
		return;

	blend = gl_IsEnabled(GL_BLEND);
	depth = gl_IsEnabled(GL_DEPTH_TEST);
	cull = gl_IsEnabled(GL_CULL_FACE);
	scissor = gl_IsEnabled(GL_SCISSOR_TEST);
	gl_GetIntegerv(0x0C10,old_scissor);
	coverage = gl_IsEnabled(GL_SAMPLE_ALPHA_TO_COVERAGE);
	gl_Disable(GL_DEPTH_TEST);
	gl_Disable(GL_CULL_FACE);
	gl_Disable(GL_SCISSOR_TEST);
	gl_Disable(GL_SAMPLE_ALPHA_TO_COVERAGE);
	gl_Enable(GL_BLEND);
	gl_BlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

	if (px != g_font_px)
		font_build(px);

	g_vertex_count = 0;
	panel(game, w, h, pack, s);

	gl_BindFramebuffer(GL_FRAMEBUFFER, 0);
	gl_Viewport(0, 0, w, h);
	gl_UseProgram(g_prog);
	gl_Uniform2f(g_loc_screen, (float)w, (float)h);
	gl_ActiveTexture(GL_TEXTURE0 + UNIT_FONT);
	gl_BindTexture(GL_TEXTURE_2D, g_font);
	gl_ActiveTexture(GL_TEXTURE0+19);gl_BindTexture(GL_TEXTURE_2D,g_logo);
	gl_BindVertexArray(g_vao);
	gl_BindBuffer(GL_ARRAY_BUFFER, g_vbo);
	gl_BufferData(GL_ARRAY_BUFFER, g_vertex_count * VERTEX_FLOATS * sizeof(float), g_vertices, GL_STREAM_DRAW);
	gl_EnableVertexAttribArray(0);
	gl_EnableVertexAttribArray(1);
	gl_EnableVertexAttribArray(2);
	gl_VertexAttribPointer(0, 2, GL_FLOAT, 0, VERTEX_FLOATS * sizeof(float), (const void *)0);
	gl_VertexAttribPointer(1, 2, GL_FLOAT, 0, VERTEX_FLOATS * sizeof(float), (const void *)(2 * sizeof(float)));
	gl_VertexAttribPointer(2, 4, GL_FLOAT, 0, VERTEX_FLOATS * sizeof(float), (const void *)(4 * sizeof(float)));
	gl_DrawArrays(GL_TRIANGLES,0,g_panel_first);
    gl_Enable(GL_SCISSOR_TEST);
    gl_Scissor(g_panel_clip[0],g_panel_clip[1],g_panel_clip[2],g_panel_clip[3]);
    gl_DrawArrays(GL_TRIANGLES,g_panel_first,g_panel_end-g_panel_first);
    gl_Disable(GL_SCISSOR_TEST);
    gl_Scissor(old_scissor[0],old_scissor[1],old_scissor[2],old_scissor[3]);
    gl_DrawArrays(GL_TRIANGLES,g_panel_end,g_vertex_count-g_panel_end);

	gl_BindBuffer(GL_ARRAY_BUFFER, s->array_buffer);
	gl_BindVertexArray(s->vao);
	gl_UseProgram(s->program);
	gl_ActiveTexture(s->active_unit);
	gl_Viewport(s->viewport[0], s->viewport[1], s->viewport[2], s->viewport[3]);
	gl_BlendFunc(s->blend_src, s->blend_dst);
	if (!blend)
		gl_Disable(GL_BLEND);
	if (depth)
		gl_Enable(GL_DEPTH_TEST);
	if (cull)
		gl_Enable(GL_CULL_FACE);
	if (scissor)
		gl_Enable(GL_SCISSOR_TEST);
	if (coverage)
		gl_Enable(GL_SAMPLE_ALPHA_TO_COVERAGE);
}
