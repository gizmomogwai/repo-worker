module screen;

import deimos.ncurses;
import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.range;
import std.stdio;
import std.string;
import std.uni;
import std.functional : unaryFun;

enum Key : int
{
    codeYes = KEY_CODE_YES,
    min = KEY_MIN,
    codeBreak = KEY_BREAK,
    down = KEY_DOWN,
    up = KEY_UP,
    left = KEY_LEFT,
    right = KEY_RIGHT,
    home = KEY_HOME,
    backspace = KEY_BACKSPACE,
    f0 = KEY_F0,
    f1 = KEY_F(1),
    f2 = KEY_F(2),
    f3 = KEY_F(3),
    f4 = KEY_F(4),
    f5 = KEY_F(5),
    f6 = KEY_F(6),
    f7 = KEY_F(7),
    f8 = KEY_F(8),
    f9 = KEY_F(9),
    f10 = KEY_F(10),
    f11 = KEY_F(11),
    f12 = KEY_F(12),
    f13 = KEY_F(13),
    f14 = KEY_F(14),
    f15 = KEY_F(15),
    f16 = KEY_F(16),
    f17 = KEY_F(17),
    f18 = KEY_F(18),
    f19 = KEY_F(19),
    f20 = KEY_F(20),
    f21 = KEY_F(21),
    f22 = KEY_F(22),
    f23 = KEY_F(23),
    f24 = KEY_F(24),
    f25 = KEY_F(25),
    f26 = KEY_F(26),
    f27 = KEY_F(27),
    f28 = KEY_F(28),
    f29 = KEY_F(29),
    f30 = KEY_F(30),
    f31 = KEY_F(31),
    f32 = KEY_F(32),
    f33 = KEY_F(33),
    f34 = KEY_F(34),
    f35 = KEY_F(35),
    f36 = KEY_F(36),
    f37 = KEY_F(37),
    f38 = KEY_F(38),
    f39 = KEY_F(39),
    f40 = KEY_F(40),
    f41 = KEY_F(41),
    f42 = KEY_F(42),
    f43 = KEY_F(43),
    f44 = KEY_F(44),
    f45 = KEY_F(45),
    f46 = KEY_F(46),
    f47 = KEY_F(47),
    f48 = KEY_F(48),
    f49 = KEY_F(49),
    f50 = KEY_F(50),
    f51 = KEY_F(51),
    f52 = KEY_F(52),
    f53 = KEY_F(53),
    f54 = KEY_F(54),
    f55 = KEY_F(55),
    f56 = KEY_F(56),
    f57 = KEY_F(57),
    f58 = KEY_F(58),
    f59 = KEY_F(59),
    f60 = KEY_F(60),
    f61 = KEY_F(61),
    f62 = KEY_F(62),
    f63 = KEY_F(63),
    dl = KEY_DL,
    il = KEY_IL,
    dc = KEY_DC,
    ic = KEY_IC,
    eic = KEY_EIC,
    clear = KEY_CLEAR,
    eos = KEY_EOS,
    eol = KEY_EOL,
    sf = KEY_SF,
    sr = KEY_SR,
    npage = KEY_NPAGE,
    ppage = KEY_PPAGE,
    stab = KEY_STAB,
    ctab = KEY_CTAB,
    catab = KEY_CATAB,
    enter = KEY_ENTER,
    sreset = KEY_SRESET,
    reset = KEY_RESET,
    print = KEY_PRINT,
    ll = KEY_LL,
    a1 = KEY_A1,
    a3 = KEY_A3,
    b2 = KEY_B2,
    c1 = KEY_C1,
    c3 = KEY_C3,
    btab = KEY_BTAB,
    beg = KEY_BEG,
    cancel = KEY_CANCEL,
    close = KEY_CLOSE,
    command = KEY_COMMAND,
    copy = KEY_COPY,
    create = KEY_CREATE,
    end = KEY_END,
    exit = KEY_EXIT,
    find = KEY_FIND,
    help = KEY_HELP,
    mark = KEY_MARK,
    message = KEY_MESSAGE,
    move = KEY_MOVE,
    next = KEY_NEXT,
    open = KEY_OPEN,
    options = KEY_OPTIONS,
    previous = KEY_PREVIOUS,
    redo = KEY_REDO,
    reference = KEY_REFERENCE,
    refresh = KEY_REFRESH,
    replace = KEY_REPLACE,
    restart = KEY_RESTART,
    resume = KEY_RESUME,
    save = KEY_SAVE,
    sbeg = KEY_SBEG,
    scancel = KEY_SCANCEL,
    scommand = KEY_SCOMMAND,
    scopy = KEY_SCOPY,
    screate = KEY_SCREATE,
    sdc = KEY_SDC,
    sdl = KEY_SDL,
    select = KEY_SELECT,
    send = KEY_SEND,
    seol = KEY_SEOL,
    sexit = KEY_SEXIT,
    sfind = KEY_SFIND,
    shelp = KEY_SHELP,
    shome = KEY_SHOME,
    sic = KEY_SIC,
    sleft = KEY_SLEFT,
    smessage = KEY_SMESSAGE,
    smove = KEY_SMOVE,
    snext = KEY_SNEXT,
    soptions = KEY_SOPTIONS,
    sprevious = KEY_SPREVIOUS,
    sprint = KEY_SPRINT,
    sredo = KEY_SREDO,
    sreplace = KEY_SREPLACE,
    sright = KEY_SRIGHT,
    srsume = KEY_SRSUME,
    ssave = KEY_SSAVE,
    ssuspend = KEY_SSUSPEND,
    sundo = KEY_SUNDO,
    suspend = KEY_SUSPEND,
    undo = KEY_UNDO,
    mouse = KEY_MOUSE,
    resize = KEY_RESIZE,
    event = KEY_EVENT,
    max = KEY_MAX,
}

enum Attributes : chtype
{
    normal = A_NORMAL,
    charText = A_CHARTEXT,
    color = A_COLOR,
    standout = A_STANDOUT,
    underline = A_UNDERLINE,
    reverse = A_REVERSE,
    blink = A_BLINK,
    dim = A_DIM,
    bold = A_BOLD,
    altCharSet = A_ALTCHARSET,
    invis = A_INVIS,
    protect = A_PROTECT,
    horizontal = A_HORIZONTAL,
    left = A_LEFT,
    low = A_LOW,
    right = A_RIGHT,
    top = A_TOP,
    vertical = A_VERTICAL,
}

void activate(Attributes attributes)
{
    (attributes & Attributes.bold) ? deimos.ncurses.curses.attron(A_BOLD)
        : deimos.ncurses.curses.attroff(A_BOLD);
    (attributes & Attributes.reverse) ? deimos.ncurses.curses.attron(A_REVERSE)
        : deimos.ncurses.curses.attroff(A_REVERSE);
    (attributes & Attributes.standout) ? deimos.ncurses.curses.attron(A_STANDOUT)
        : deimos.ncurses.curses.attroff(A_STANDOUT);
    (attributes & Attributes.underline) ? deimos.ncurses.curses.attron(A_UNDERLINE)
        : deimos.ncurses.curses.attroff(A_UNDERLINE);
}

/// either a special key like arrow or backspace
/// or an utf-8 string (e.g. ä is already 2 bytes in an utf-8 string)
struct KeyInput
{
    bool specialKey;
    wint_t key;
    string input;
    this(bool specialKey, wint_t key, string input)
    {
        this.specialKey = specialKey;
        this.key = key;
        this.input = input.dup;
    }

    static KeyInput fromSpecialKey(wint_t key)
    {
        return KeyInput(true, key, "");
    }

    static KeyInput fromText(string s)
    {
        return KeyInput(false, 0, s);
    }
}

class NoKeyException : Exception
{
    this(string s)
    {
        super(s);
    }
}

class Screen
{
    File tty;
    SCREEN* screen;
    WINDOW* window;
    this(string file)
    {
        this.tty = File("/dev/tty", "r+");
        this.screen = newterm(null, tty.getFP, tty.getFP);
        this.screen.set_term;
        this.window = stdscr;
        deimos.ncurses.curses.noecho;
        deimos.ncurses.curses.halfdelay(1);
        deimos.ncurses.curses.keypad(this.window, true);
        deimos.ncurses.curses.curs_set(0);
        deimos.ncurses.curses.wtimeout(this.window, 50);
    }

    ~this()
    {
        deimos.ncurses.curses.endwin;
        this.screen.delscreen;
    }

    auto clear()
    {
        int res = nclear;
        // todo error handling
        return this;
    }

    auto refresh()
    {
        deimos.ncurses.curses.refresh;
        // todo error handling
        return this;
    }

    auto update()
    {
        deimos.ncurses.curses.doupdate;
        // todo error handling
        return this;
    }

    int width() @property
    {
        return deimos.ncurses.curses.getmaxx(this.window) + 1;
    }

    int height() @property
    {
        return deimos.ncurses.curses.getmaxy(this.window) + 1;
    }

    auto addstring(int y, int x, string text)
    {
        deimos.ncurses.curses.move(y, x);
        deimos.ncurses.curses.addstr(text.toStringz);
        return this;
    }

    auto addstring(Range)(int y, int x, Range str)
    {
        deimos.ncurses.curses.move(y, x);
        addstring(str);
        return this;
    }

    void addstring(Range)(Range str)
    {
        foreach (grapheme, attribute; str)
        {
            attribute.activate;
            deimos.ncurses.curses.addstr(text(grapheme[]).toStringz);
            deimos.ncurses.curses.attrset(A_NORMAL);
        }
    }

    int currentX() @property
    {
        return deimos.ncurses.curses.getcurx(this.window);
    }

    int currentY() @property
    {
        return deimos.ncurses.curses.getcury(this.window);
    }

    auto getWideCharacter()
    {
        wint_t key1;
        int res = wget_wch(this.window, &key1);
        switch (res)
        {
        case KEY_CODE_YES:
            return KeyInput.fromSpecialKey(key1);
        case OK:
            return KeyInput.fromText(key1.to!string);
        default:
            throw new NoKeyException("Could not read a wide character");
        }
    }
}

int byteCount(int k)
{
    if (k < 0b1100_0000)
    {
        return 1;
    }
    if (k < 0b1110_0000)
    {
        return 2;
    }

    if (k > 0b1111_0000)
    {
        return 3;
    }

    return 4;
}

@("test strings") unittest
{
    string s = ['d'];
    writeln(KeyInput.fromText(s));
    import std.stdio;

    writeln(s.length);
}

abstract class Component {
    int left;
    int top;
    int right;
    int bottom;
    void resize(int left, int top, int right, int bottom) {
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }
    abstract void render(Screen screen);
    void up() {
    }
    void down() {
    }
    int height() {
        return bottom-top;
    }
    int width() {
        return right-left;
    }
}

class VSplit : Component {
    float split;
    Component left;
    Component right;
    this(float split, Component left, Component right) {
        this.split = split;
        this.left = left;
        this.right = right;
    }
    override void resize(int left, int top, int right, int bottom) {
        int splitPos = left + ((right-left)*split).to!int;
        this.left.resize(left, top, splitPos , bottom);
        this.right.resize(splitPos, top, right, bottom);
        super.resize(left, top, right, bottom);
    }
    override void render(Screen screen) {
        left.render(screen);
        right.render(screen);
    }
    override void up() {
        left.up();
    }
    override void down() {
        left.down();
    }
}

class Filled : Component {
    string what;
    this(string what) {
        this.what = what;
    }
    override void render(Screen screen) {
        for (int y=top; y<bottom; y++) {
            for (int x=left; x<right; x++) {
                screen.addstring(y, x, what);
            }
        }
        screen.addstring(top, left, "0");
        screen.addstring(bottom-1, right-1, "1");
    }
}

class List(T, alias stringTransform) : Component
{
    T[] model;
    struct ScrollInfo {
        int selection;
        int offset;
        void up() {
            if (selection > 0) {
                selection--;
                while (selection < offset)
                {
                    offset--;
                }
            }
        }
        void down(T[] model, int height)
        {
            if (selection < model.length - 1)
            {
                selection++;
                while (selection >= offset + height)
                {
                    offset++;
                }
            }
        }
    }
    ScrollInfo scrollInfo;
    this(T[] model)
    {
        this.model = model;
        this.scrollInfo = ScrollInfo(0, 0);
    }
    override void render(Screen screen)
    {
        for (int i=0; i<height; ++i)
        {
            auto index = i+scrollInfo.offset;
            if (index >= model.length) return;
            auto text = (index == scrollInfo.selection ? "> %s" : "  %s")
                .format(stringTransform(model[index]))
                .take(width())
                .to!string;
            screen.addstring(top+i, left, text);
        }
    }
    override void up()
    {
        scrollInfo.up;
    }
    override void down()
    {
        scrollInfo.down(model, height);
    }
}

    /+class List : NCursesComponent
{
    class Details {
        long selection;
        this() {
            this.selection = 0;
        }
    }
    Screen screen;
    GitCommit[] model;

    this(Screen screen, GitCommit[] model)
    {
        this.screen = screen;
        this.model = model;
        this.details = new Details();
    }

    /// return selection
    string get()
    {
        if (details.selection == -1)
        {
            return "";
        }
        return model[details.selection];
    }

    void resize()
    {
        height = screen.height - 2;
        details.offset = 0;
        details.selection = 0;
    }

    void selectUp()
    {
        if (details.selection < allMatches.length - 1)
        {
            details.selection++;
            // correct selection to be in the right range.
            // we check only the upper limit, as we just incremented the selection
            while (details.selection >= details.offset + height)
            {
                details.offset++;
            }
        }
    }

    void selectDown()
    {
        if (details.selection > 0)
        {
            details.selection--;
            // correct selection to be in the right range.
            // we check only the lower limit, as we just decremented the selection
            while (details.selection < details.offset)
            {
                details.offset--;
            }
        }
    }

    private void adjustOffsetAndSelection()
    {
        details.selection = min(details.selection, allMatches.length - 1);

        if (allMatches.length < height)
        {
            details.offset = 0;
        }
        if (details.selection < details.offset)
        {
            details.offset = details.selection;
        }
    }
    /// render the list
}
+/

class Ui(State) {
    Screen screen;
    Component root;
    this(Screen screen, Component root) {
        this.screen = screen;
        this.root = root;
    }
    void render() {
        try
        {
            // ncurses
            screen.clear;

            // own api
            root.render(screen);
            // status.render;

            // ncurses
            screen.refresh;
            screen.update;
        }
        catch (Exception e)
        {
            import std.experimental.logger : error;
            e.to!string.error;
        }
    }
    abstract State handleKey(KeyInput input, State state);
}

