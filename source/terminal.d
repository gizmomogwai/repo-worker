module terminal;


import core.sys.posix.termios;
import core.sys.posix.unistd;
import core.sys.posix.sys.ioctl;
import core.stdc.stdio;
import core.stdc.ctype;
import std.signals : Signal;

import std.stdio;
import std;
import std.conv : to;
alias Position = Tuple!(int, "x", int, "y");
alias Dimension = Tuple!(int, "width", int, "height"); /// https://en.wikipedia.org/wiki/ANSI_escape_code

enum Operation : string
{

    CURSOR_UP = "A",
    CURSOR_DOWN = "B",
    CURSOR_FORWARD = "C",
    CURSOR_BACKWARD = "D",
    CURSOR_POSITION = "H",
    ERASE_IN_DISPLAY = "J",
    ERASE_IN_LINE = "K",
    DEVICE_STATUS_REPORT = "n",
    CURSOR_POSITION_REPORT = "R",
    CLEAR_TERMINAL = "2J",
    CLEAR_LINE = "2K",
}

enum State : string {
    CURSOR = "?25",
    ALTERNATE_BUFFER = "?1049",
}

enum Mode : string {
    LOW = "l",
    HIGH = "h",
}


/+    static string esc(Operation operation, string arg) {
        string result = "\x1b[";
        result ~= arg;
        result ~= operation;
        return result;
    }
    +/
/+
    static string esc(Args...)(Operation operation, Args args)
    {
        string result = "\x1b[";
        result ~= [args].join(";").joiner;
        result ~= operation;
        return result;
    }
+/
/+
    static string moveRight(int steps)
    {
        return esc(Operation.CURSOR_FORWARD, "%d".format(steps));
    }

    static string moveDown(int steps)
    {
        return esc(Operation.CURSOR_DOWN, "%d".format(steps));
    }

    static Position getCursorPosition()
    {
        auto get = esc(Operation.DEVICE_STATUS_REPORT, "6");
        (core.sys.posix.unistd.write(2, get.ptr, get.length) == get.length).errnoEnforce(
                "Cannot request cursor position");

        long bytesRead;
        string position;
        {
            int result;
            while ((bytesRead = core.sys.posix.unistd.read(1, &result, 1)) == 1)
            {
                position ~= result;
            }
        }

        Position result;
        (2 == position.formattedRead!(esc(VT.Operation.CURSOR_POSITION_REPORT,
                "%d", "%d"))(result.y, result.x)).enforce("Cannot parse position");
        return result;
    }
        +/
/+
    static Dimension getDimension()
    {
        auto hideCursor = VT.esc(VT.Operation.HIDE_CURSOR, "?25");
        (core.sys.posix.unistd.write(2, hideCursor.ptr, hideCursor.length) == hideCursor.length).errnoEnforce(
                "Cannot hide cursor");
        scope (exit)
        {
            auto showCursor = VT.esc(VT.Operation.SHOW_CURSOR, "?25");
            (core.sys.posix.unistd.write(2, showCursor.ptr, showCursor.length) == showCursor.length).errnoEnforce(
                    "Cannot show cursor");
        }

        auto move = moveRight(999) ~ moveDown(999);
        (core.sys.posix.unistd.write(2, move.ptr, move.length) == move.length).errnoEnforce(
                "Cannot move to right bottom");

        auto position = getCursorPosition();
        return Dimension(position.x, position.y);
    }
    +/


string execute(Operation operation)
{
    return "\x1b[" ~ operation;
}

string execute(Operation operation, string[] args...) {
    return "\x1b[" ~ args.join(";") ~ operation;
}

string to(State state, Mode mode) {
    return "\x1b[" ~ state ~ mode;
}


Terminal INSTANCE;
class Terminal {
    termios originalState;
    this() {
        (tcgetattr(1, &originalState) == 0).errnoEnforce("Cannot get termios");
        termios newState = originalState;
        newState.c_lflag &= ~(ECHO | ICANON);
        (tcsetattr(1, TCSAFLUSH, &newState) == 0).errnoEnforce("Cannot set termios");

        auto data =
            State.ALTERNATE_BUFFER.to(Mode.HIGH) ~
            Operation.CLEAR_TERMINAL.execute ~
            State.CURSOR.to(Mode.LOW);
        w(data, "Cannot initialize terminal");
    }
    void resize(Component root) {
        auto d = dimension;
        root.resize(0, 0, d.width-1, d.height-1);
        root.render(this);
    }
    auto putString(string s) {
        w(s, "Cannot write string");
        return this;
    }

    auto xy(int x, int y) {
        w(Operation.CURSOR_POSITION.execute((y+1).to!string, (x+1).to!string), "Cannot position cursor");
        return this;
    }

    final void w(string data, lazy string errorMessage) {
        (core.sys.posix.unistd.write(2, data.ptr, data.length) == data.length).errnoEnforce(
          errorMessage);
    }

    auto clear() {
        w(Operation.CLEAR_TERMINAL.execute, "Cannot clear terminal");
        return this;
    }
    ~this() {
        auto data =
            State.ALTERNATE_BUFFER.to(Mode.HIGH) ~
            Operation.CLEAR_TERMINAL.execute ~
            State.CURSOR.to(Mode.HIGH) ~
            State.ALTERNATE_BUFFER.to(Mode.LOW);
        (core.sys.posix.unistd.write(2, data.ptr, data.length) == data.length).errnoEnforce(
          "Cannot deinitialize terminal");

        (tcsetattr(1, TCSANOW, &originalState) == 0).errnoEnforce("Cannot set termios");
    }
    Dimension dimension() {
        winsize ws;
        (ioctl(1, TIOCGWINSZ, &ws) == 0).errnoEnforce("Cannot get winsize");
        return Dimension(ws.ws_col, ws.ws_row);
    }
    KeyInput getInput() {
        int c;
        (core.sys.posix.unistd.read(1, &c, 1) == 1).errnoEnforce("Cannot read next input");
        return KeyInput.fromText("" ~ cast(char)c);
    }
}
/+
import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.range;
import std.stdio;
import std.string;
import std.uni;
import std.functional : unaryFun;
+/
enum Key : int
{
    down = 1,
    up = 2,
    /+
    codeYes = KEY_CODE_YES,
    min = KEY_MIN,
    codeBreak = KEY_BREAK,
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
    +/
}
/+
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


+/
/// either a special key like arrow or backspace
/// or an utf-8 string (e.g. ä is already 2 bytes in an utf-8 string)
struct KeyInput
{
    bool specialKey;
    string input;
    this(bool specialKey, string input)
    {
        this.specialKey = specialKey;
        this.input = input.dup;
    }

    static KeyInput fromText(string s)
    {
        return KeyInput(false, s);
    }
}

class NoKeyException : Exception
{
    this(string s)
    {
        super(s);
    }
}
/+
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
+/
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
    abstract void render(Terminal terminal);
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
    SumType!(int, float) split;
    Component left;
    Component right;
    this(float split, Component left, Component right) {
        this.split = split;
        this.left = left;
        this.right = right;
    }
    this(int split, Component left, Component right) {
        this.split = split;
        this.left = left;
        this.right = right;
    }
    override void resize(int left, int top, int right, int bottom) {
        split.match!(
          (int split) {
              int splitPos = split;
              this.left.resize(left, top, splitPos , bottom);
              this.right.resize(splitPos, top, right, bottom);
          },
          (float split) {
              int splitPos = left + ((right-left)*split).to!int;
              this.left.resize(left, top, splitPos , bottom);
              this.right.resize(splitPos, top, right, bottom);
          }
        );
        super.resize(left, top, right, bottom);
    }
    override void render(Terminal terminal) {
        left.render(terminal);
        right.render(terminal);
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
    override void render(Terminal terminal) {
        for (int y=top; y<bottom; y++) {
            for (int x=left; x<right; x++) {
                terminal.xy(x, y).putString(what);
            }
        }
        terminal.xy(left, top).putString("0");
        terminal.xy(right-1, bottom-1).putString("1");
    }
}

string takeIgnoreAnsiEscapes(string s, uint length) {
    string result;
    uint count = 0;
    bool inColorAnsiEscape = false;
    while (!s.empty) {
        auto current = s.front;
        if (current == 27) {
            inColorAnsiEscape = true;
            result ~= current;
        } else {
            if (inColorAnsiEscape) {
                result ~= current;
                if (current == 'm') {
                    inColorAnsiEscape = false;
                }
            } else {
                if (count < length) {
                    result ~= current;
                    count++;
                }
            }
        }
        s.popFront;
    }
    return result;
}

@("takeIgnoreAnsiEscapes") unittest {
    import unit_threaded;
    "hello world".takeIgnoreAnsiEscapes(5).should == "hello";
    "he\033[123mllo world\033[0m".takeIgnoreAnsiEscapes(5).should == "he\033[123mllo\033[0m";
    "köstlin".takeIgnoreAnsiEscapes(7).should == "köstlin";
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
    mixin Signal!(T) selectionChanged;
    this(T[] model)
    {
        this.model = model;
        this.scrollInfo = ScrollInfo(0, 0);
    }
    override void render(Terminal terminal)
    {
        for (int i=0; i<height; ++i)
        {
            auto index = i+scrollInfo.offset;
            if (index >= model.length) return;
            auto text = (index == scrollInfo.selection ? "> %s" : "  %s")
                .format(stringTransform(model[index]))
                .takeIgnoreAnsiEscapes(width())
                .to!string;
            terminal.xy(left, top+i).putString(text);
        }
    }
    override void up()
    {
        scrollInfo.up;
        selectionChanged.emit(model[scrollInfo.selection]);
    }
    override void down()
    {
        scrollInfo.down(model, height);
        selectionChanged.emit(model[scrollInfo.selection]);
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

extern(C) void signal(int sig, void function(int) );
UiInterface theUi;
extern(C) void windowSizeChangedSignalHandler(int sig) {
    theUi.resized();
}

abstract class UiInterface {
    void resized();
}
class Ui(State) : UiInterface{
    Terminal terminal;
    Component root;
    this(Terminal terminal, Component root) {
        this.terminal = terminal;
        this.root = root;
        theUi = this;
        signal(28, &windowSizeChangedSignalHandler);
    }
    void render() {
        try
        {
            terminal.clear;
            root.render(terminal);
        }
        catch (Exception e)
        {
            import std.experimental.logger : error;
            e.to!string.error;
        }
    }
    override void resized() {
        auto dimension = terminal.dimension;
        root.resize(0, 0, dimension.width, dimension.height);
        render;
    }
    abstract State handleKey(KeyInput input, State state);
}

