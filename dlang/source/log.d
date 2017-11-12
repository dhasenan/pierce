module pierce.log;

import std.experimental.logger;
import std.datetime;

class VibeRollingFileLogger : Logger
{
    import std.format : format;
    import vibe.core.file : existsFile, FileMode, FileStream, openFile;

    this(in string fileFormat, const LogLevel lv, size_t maxFileSize = 1024 * 1024 * 10)
    {
        import std.file : exists, mkdirRecurse;
        import std.path : dirName;
        import std.conv : text;
        super(lv);
        this.fileFormat = fileFormat;
        this.maxFileSize = maxFileSize;
    }

    override protected void writeLogMsg(ref LogEntry payload) @trusted
    {
        import std.string : lastIndexOf;
        ptrdiff_t fnIdx = payload.file.lastIndexOf('/') + 1;
        ptrdiff_t funIdx = payload.funcName.lastIndexOf('.') + 1;
        getFile().write("%s:%s:%s:%u %s\n".format(
            payload.timestamp.toISOString,
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
            fileDate = date;
            index = 0;
        }
        foreach (i; 0..100)
        {
            auto name = formatFilename(fileFormat, fileDate, index);
            if (!existsFile(name))
            {
                file = openFile(name, FileMode.append);
                return file;
            }
            index++;
        }
        throw new Exception("tried creating new file " ~
                "but you have an excessive number of old logfiles for this same date");
    }
}

private string formatFilename(string fileFormat, Date date, size_t index)
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
                case '%':
                    ap ~= '%';
                    break;
                case 'y':
                    ap ~= date.year.to!string;
                    break;
                case 'm':
                    ap ~= date.month.to!string;
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
