import std.string;
import std.stdio;
import std.concurrency;
import colored;
import std.conv;

abstract class State
{
    int channel;
    string[int] channels;
    Tid receiver;
    this(int channel, string[int] channels, Tid receiver)
    {
        this.channel = channel;
        this.channels = channels;
        this.receiver = receiver;
    }

    abstract State handleInput(ubyte b);
}

class NormalState : State
{
    this(int channel, string[int] channels, Tid receiver)
    {
        super(channel, channels, receiver);
    }

    override State handleInput(ubyte b)
    {
        if (b == 0xff)
        {
            return new FFState(channel, channels, receiver);
        }

        if (b == '\n')
        {
            receiver.send(channel, channels[channel].idup);
            channels[channel] = "";
        }
        else
        {
            channels[channel] ~= cast(dchar) b;
        }
        return this;
    }
}

class FFState : State
{
    this(int channel, string[int] channels, Tid receiver)
    {
        super(channel, channels, receiver);
    }

    override State handleInput(ubyte b)
    {
        if (b == 0xff)
        {
            channels[channel] ~= cast(dchar) b;
            return this;
        }
        return new NormalState(b, channels, receiver);
    }
}

struct Finished
{
}

void readStdin()
{
    string[int] channels;
    State state = new NormalState(0, channels, ownerTid);

    ubyte[1] buffer;
    auto read = stdin.rawRead(buffer);
    while (read.length == 1)
    {
        auto b = read[0];
        state = state.handleInput(b);
        read = stdin.rawRead(buffer);
    }
}

class ConsoleState
{
    abstract ConsoleState process(ubyte b);
}

class NormalConsoleState : ConsoleState
{
    override ConsoleState process(ubyte b)
    {
        if (b == 27)
        {
            return new SwitchOutputState();
        }
        return this;
    }
}

class SwitchOutputState : ConsoleState
{
    string console = "";
    override ConsoleState process(ubyte b)
    {
        if (b == 10)
        {
            ubyte[] command = [0xff, console.to!ubyte];
            stdout.rawWrite(command);
            return new NormalConsoleState();
        }
        console ~= cast(dchar) b;
        return this;
    }
}

void ttyReader()
{
    auto tty = File("/dev/tty", "r+");
    ubyte[1] buffer;
    ConsoleState state = new NormalConsoleState();
    while (true)
    {
        auto read = tty.rawRead(buffer);
        if (read.length == 0)
        {
            return;
        }
        state = state.process(read[0]);
    }
}

void main()
{
    auto reader = spawnLinked(&readStdin);
    auto keyreader = spawnLinked(&ttyReader);

    bool finished = false;
    while (!finished)
    {
        receive((int channel, string line) {
            import std.digest.sha;
            import std.algorithm;

            auto color = sha1Of([channel]);
            writeln(RGBString("%s: %s".format(channel,
                line.filterAnsiEscapes!(style))).rgb(color[0], color[1], color[2]).toString);
        }, (LinkTerminated lt) { finished = true; },);
    }
}
