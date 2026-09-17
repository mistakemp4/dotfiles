using System.Text.RegularExpressions;
using CriFsV2Lib;
using CriFsV2Lib.Definitions;
using CriFsV2Lib.Definitions.Structs;

if (args.Length < 2 || (args[0] == "extract" && args.Length != 4))
{
    Console.Error.WriteLine("usage: list <cpk> | extract <cpk> <outdir> <regex>");
    return 1;
}

var decrypt = CriFsLib.Instance.GetKnownDecryptionFunction(KnownDecryptionFunction.P5R);
using var stream = new FileStream(args[1], FileMode.Open, FileAccess.Read);
using var reader = CriFsLib.Instance.CreateCpkReader(stream, false, decrypt);
var files = reader.GetFiles();

static string PathOf(CpkFile f) => string.IsNullOrEmpty(f.Directory) ? f.FileName : $"{f.Directory}/{f.FileName}";

if (args[0] == "list")
{
    foreach (var f in files)
        Console.WriteLine($"{f.ExtractSize}\t{PathOf(f)}");
    return 0;
}

var pattern = new Regex(args[3], RegexOptions.IgnoreCase);
var root = Path.GetFullPath(args[2]);
var count = 0;
foreach (var f in files)
{
    var path = PathOf(f);
    if (!pattern.IsMatch(path))
        continue;
    // archive paths must stay inside the output folder
    var dest = Path.GetFullPath(Path.Combine(root, path));
    if (!dest.StartsWith(root + Path.DirectorySeparatorChar))
        continue;
    Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
    using var data = reader.ExtractFile(f);
    // RawArray is pooled and can be longer than the file
    File.WriteAllBytes(dest, data.RawArray.AsSpan(0, f.ExtractSize));
    Console.WriteLine(path);
    count++;
}
Console.Error.WriteLine($"extracted {count}");
return 0;
