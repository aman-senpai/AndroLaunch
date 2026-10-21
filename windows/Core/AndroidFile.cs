using System;
using System.IO;

namespace Androlaunch.Core
{
    public sealed class AndroidFile
    {
        public string Name { get; init; } = "";
        public string Path { get; init; } = "";
        public long Size { get; init; }
        public string? ModificationDate { get; init; }
        public bool IsDirectory { get; init; }
        public string Permissions { get; init; } = "";

        public string Extension => System.IO.Path.GetExtension(Name).TrimStart('.').ToLowerInvariant();

        public string FormattedSize
        {
            get
            {
                if (IsDirectory)
                {
                    return "—";
                }

                string[] units = { "B", "KB", "MB", "GB", "TB" };
                double value = Size;
                int unit = 0;
                while (value >= 1024 && unit < units.Length - 1)
                {
                    value /= 1024;
                    unit++;
                }

                return unit == 0
                    ? $"{Size} B"
                    : $"{value:0.#} {units[unit]}";
            }
        }

        public string Kind
        {
            get
            {
                if (IsDirectory)
                {
                    return "Folder";
                }

                return Extension switch
                {
                    "jpg" or "jpeg" or "png" or "gif" or "webp" or "bmp" or "heic" => "Image",
                    "mp4" or "mkv" or "mov" or "webm" or "3gp" => "Video",
                    "mp3" or "wav" or "m4a" or "flac" or "ogg" => "Audio",
                    "apk" => "Android package",
                    "zip" or "rar" or "7z" or "tar" or "gz" => "Archive",
                    "txt" or "md" or "log" or "json" or "xml" => "Text",
                    "pdf" => "PDF",
                    _ => string.IsNullOrEmpty(Extension) ? "File" : Extension.ToUpperInvariant()
                };
            }
        }

        public override string ToString() => Name;
    }
}
