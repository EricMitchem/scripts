///////////////////////////////////////////////////////////////////////////////
/// Eric Mitchem
/// July 13, 2014
/// VLC Transcoder
/// Receives video files to be transcoded by vlc. It will never modify the
/// original videos. It will read, transcode if possible, and then write out to
/// new files.
///////////////////////////////////////////////////////////////////////////////
module vlc_transcoder;

///////////////////////////////////////////////////////////////////////////////
/// Imports
///////////////////////////////////////////////////////////////////////////////
import std.algorithm;
import std.array;
import std.file;
import std.getopt;
import std.path;
import std.process;
import std.stdio;
import std.string;
import std.traits;

string vlcopts = " --no-qt-notification"          // No message popups
" --qt-start-minimized"          // SysTrayIcon only
" --play-and-exit"               // Exit after transcoding
" --no-sout-transcode-hurry-up"; // Don't drop frames

string vlc = r"C:\Program Files (x86)\VideoLAN\VLC\vlc.exe";
string[] input;              // Input files/dirs
string output;               // Output directory
bool recurseInput = false;   // Recursively searches input directories
string[] containers;         // File containers (well, supported extensions)
string outContainer = "mp4"; // Transcode output container
string vcodec = "h264";      // Video codec
uint vb = 0;                 // Video bitrate, kbit/s
float scale = 1.0f;          // Video rescale ratio
string acodec = "mp3";       // Audio codec
uint ab = 96;                // Audio bitrate, kbit/s
uint channels = 2;           // Audio channels
uint samplerate = 44100;     // Audio sample rate
bool simulate = false;       // Don't actually make any changes
bool help = false;           // "help"

int main(string[] args)
{
    containers ~= "mp4";
    containers ~= "webm";

    getopt(args,
           "vlc", &vlc,
           "input", &input,
           "output", &output,
           "r", &recurseInput,
           "container", &containers,
           "outcontainer", &outContainer,
           "vcodec", &vcodec,
           "vb", &vb,
           "scale", &scale,
           "acodec", &acodec,
           "ab", &ab,
           "channels", &channels,
           "samplerate", &samplerate,
           "s", &simulate,
           "h|help", &help);

    if(help)
        return usage();

    if(simulate)
        writeln("Simulating..");

    if(!vlc.isValidPath() || !vlc.exists())
    {
        writefln("Invalid vlc path: %s", vlc);
        return 1;
    }

    if(!output.back.isDirSeparator())
        output ~= dirSeparator;

    if(!output.isValidPath())
    {
        writefln("Invalid output path: %s", output);
        return -1;
    }

    if(!output.exists())
    {
        writefln("Making output path: %s", output);

        if(!simulate)
            mkdirRecurse(output);
    }

    expandInput();

    if(input.empty)
    {
        writeln("No input");
        return 0;
    }

    string command = buildCommand();
    int status = 0;

    if(!simulate)
    {
        writefln("Executing: %s", command);
        auto ret = executeShell(command);

        writeln("[VLC]");
        writeln(ret.output);
        writeln("[/VLC]");

        status = ret.status;
    }

    else
    {
        writefln("Command: %s", command);
    }

    writeln("Done");
    return status;
}

///////////////////////////////////////////////////////////////////////////////
/// Builds the command to be executed in the shell.
///////////////////////////////////////////////////////////////////////////////
string buildCommand()
{
    string command = '"' ~ vlc ~ '"' ~ vlcopts;

    writeln("[Output Files]");
    foreach(i; input)
    {
        string basename = i.stripExtension() ~ "." ~ outContainer;
        basename = basename.replace(['\\'], ['_']). // Dir seperator
                            replace(['/'], ['_']). // Dir seperator
                            replace([':'], ['_']). // Drive letter
                            replace(['-'], ['_']); // Looks better
        string dst = output ~ "vlct-" ~ basename;
        writefln("\t%s", dst);

        command ~= format(" %s "
                          ":sout=#transcode{"
                          "vcodec=%s,"
                          "vb=%s,"
                          "scale=%s,"
                          "acodec=%s,"
                          "ab=%s,"
                          "channels=%s,"
                          "samplerate=%s}"
                          ":file{dst=\"%s\"}",
                          '"' ~ i ~ '"', vcodec, vb, scale, acodec, ab,
                          channels, samplerate, dst);
    }
    writeln("[/Output Files]");

    return command;
}

///////////////////////////////////////////////////////////////////////////////
/// Expands directories (recursively, if enabled) to files.
///////////////////////////////////////////////////////////////////////////////
void expandInput()
{
    if(input.empty)
        return;

    writeln("[All Input]");
    foreach(i; input)
        writefln("\t%s", i);
    writeln("[/All Input]");

    writeln("Filtering non-existent files");
    input = input.filter!((a) => a.exists()).array;

    writeln("[Existent Input]");
    foreach(i; input)
        writefln("\t%s", i);
    writeln("[/Existent Input]");

    writeln("[Container Whitelist])");
    foreach(c; containers)
        writefln("\t%s", c);
    writeln("[/Container Whitelist])");

    writeln("Splitting directories and files");
    string[] dirs = input.filter!((a) => a.isDir()).array;
    string[] files = input.filter!((a) => a.isFile() && !a.isDir()).
        filter!((a) => a.containerMatch()).
        map!((a) => a.absolutePath()).
        map!((a) => a.buildNormalizedPath()).array;

    writeln("[Directories]");
    foreach(d; dirs)
        writefln("\t%s", d);
    writeln("[/Directories]");

    writeln("[Files]");
    foreach(f; files)
        writefln("\t%s", f);
    writeln("[/Files]");

    auto span = (recurseInput) ? SpanMode.breadth : SpanMode.shallow;
    writefln("Recursive: %s", (recurseInput) ? "true" : "false");

    foreach(d; dirs)
    {
        writefln("[Expand Dir: %s]", d);
        foreach(e; dirEntries(d, span).filter!((a) => a.isFile() && a.containerMatch()))
        {
            string file = e.name.absolutePath().buildNormalizedPath();
            writefln("\tAdd: %s", file);
            files ~= file;
        }
        writefln("[/Expand Dir: %s]", d);
    }

    writeln("[Expanded Files]");
    foreach(f; files)
        writefln("\t%s", f);
    writeln("[/Expanded Files]");

    writeln("Removing duplicate files");
    input = files.uniq().array;

    writeln("[Final Input Files]");
    foreach(i; input)
        writefln("\t%s", i);
    writeln("[/Final Input Files]");
}

///////////////////////////////////////////////////////////////////////////////
/// Returns true if the file matches a supported container.
///////////////////////////////////////////////////////////////////////////////
bool containerMatch(string filename)
{
    foreach(c; containers)
        if(filename.globMatch("*." ~ c))
            return true;

    return false;
}

///////////////////////////////////////////////////////////////////////////////
/// Outputs the program usage.
///////////////////////////////////////////////////////////////////////////////
int usage()
{
    return 0;
}
