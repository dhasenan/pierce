module pierce.log;

import pierce.datetimeformat;
import std.experimental.logger;
import std.datetime;

__gshared MultiLogger logger;
shared static this()
{
    import std.stdio : stderr;
    logger = new MultiLogger;
    logger.insertLogger("console", new std.experimental.logger.FileLogger(stderr));
    sharedLog = logger;
}

class VibeRollingFileLogger : Logger
{
    import std.format : format;
    import vibe.core.file : existsFile, getFileInfo, FileMode, FileStream, openFile;

    this(in string fileFormat, string id, const LogLevel lv, size_t maxFileSize = 1024 * 1024 * 10)
    {
        super(lv);
        this.fileFormat = fileFormat;
        this.id = id;
        this.maxFileSize = maxFileSize;
    }

    override protected void writeLogMsg(ref LogEntry payload) @trusted
    {
        import std.string : lastIndexOf;
        ptrdiff_t fnIdx = payload.file.lastIndexOf('/') + 1;
        ptrdiff_t funIdx = payload.funcName.lastIndexOf('.') + 1;
        getFile().write("%s %s %s:%s:%u %s\n".format(
            pierce.datetimeformat.format(payload.timestamp, ISO8601FORMAT),
            payload.logLevel,
            payload.file[fnIdx..$],
            payload.funcName[funIdx..$],
            payload.line,
            payload.msg));
    }

private:
    FileStream file;
    string fileFormat;
    Date fileDate;
    size_t maxFileSize;
    size_t index;
    string id;

    FileStream getFile()
    {
        auto date = cast(Date)Clock.currTime();
        if (date == fileDate)
        {
            if (file !is null)
            {
                if (file.size >= maxFileSize)
                {
                    file.close;
                    index++;
                }
                else
                {
                    return file;
                }
            }
        }
        else
        {
            if (file) file.close;
            fileDate = date;
            index = 0;
        }
        foreach (i; 0..100)
        {
            auto name = formatFilename(fileFormat, fileDate, index, id);
            if (existsFile(name))
            {
                auto info = getFileInfo(name);
                if (info.size >= maxFileSize)
                {
                    index++;
                    continue;
                }
            }
            file = openFile(name, FileMode.append);
            return file;
        }
        throw new Exception("tried creating new file " ~
                "but you have an excessive number of old logfiles for this same date");
    }
}

private string formatFilename(string fileFormat, Date date, size_t index, string id)
{
    import std.array : Appender;
    import std.conv : to;

    Appender!string ap;
    bool inEscape = false;
    foreach (i, c; fileFormat)
    {
        if (inEscape)
        {
            switch (c)
            {
                case 'n':
                    ap ~= id;
                    break;
                case '%':
                    ap ~= '%';
                    break;
                case 'y':
                    ap ~= date.year.to!string;
                    break;
                case 'm':
                    ap ~= (cast(int)date.month).to!string;
                    break;
                case 'd':
                    ap ~= date.day.to!string;
                    break;
                case 'i':
                    ap ~= index.to!string;
                    break;
                default:
                    ap ~= '%';
                    ap ~= c;
            }
            inEscape = false;
        }
        else if (c == '%')
        {
            inEscape = true;
        }
        else
        {
            ap ~= c;
        }
    }
    return ap.data.idup;
}
