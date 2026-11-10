using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

static class VireForeign
{
    const uint SearchFlags = 0x900;
    const int MaxForeignText = 4096;

    public static int Call(string root, object dllValue, object exportValue, int line, int col)
    {
        return CallArgs(root, dllValue, exportValue, new int[0], line, col);
    }

    public static int CallArgs(string root, object dll, object export, int[] args, int line, int col)
    {
        if (args == null || args.Length > 4)
            throw new VireError("foreign takes at most 4 numbers", line, col);
        object[] boxed = new object[args.Length];
        for (int i = 0; i < args.Length; i++) boxed[i] = args[i];
        return (int)Invoke(root, dll, export, boxed, false, line, col);
    }

    // "text" or "number" in the third slot is a result kind, not a DLL argument.
    // Text crosses as a NUL-terminated UTF-8 pointer. Text comes back as const char*.
    public static object CallProgram(string root, List<object> args, int line, int col)
    {
        if (args == null || args.Count < 2 || args.Count > 7)
            throw new VireError("foreign takes 2 to 7 values, got " + (args == null ? 0 : args.Count), line, col);
        bool asText = false;
        int from = 2;
        if (args.Count > 2 && args[2] is string flag && (flag == "text" || flag == "number"))
        {
            asText = flag == "text";
            from = 3;
        }
        int count = args.Count - from;
        if (count > 4)
            throw new VireError("foreign takes at most 4 values", line, col);
        object[] native = new object[count];
        for (int i = 0; i < count; i++)
        {
            object item = args[from + i];
            if (!(item is int) && !(item is string))
                throw new VireError("foreign needs whole numbers or text", line, col);
            native[i] = item;
        }
        return Invoke(root, args[0], args[1], native, asText, line, col);
    }

    static object Invoke(string root, object dll, object export, object[] args, bool asText, int line, int col)
    {
        IntPtr module;
        bool already;
        IntPtr proc = LoadExport(root, dll, export, line, col, out module, out already);
        GCHandle[] pins = new GCHandle[args.Length];
        int pinsUsed = 0;
        try
        {
            IntPtr a0 = IntPtr.Zero;
            IntPtr a1 = IntPtr.Zero;
            IntPtr a2 = IntPtr.Zero;
            IntPtr a3 = IntPtr.Zero;
            for (int i = 0; i < args.Length; i++)
            {
                IntPtr slot;
                if (args[i] is int n) slot = new IntPtr(n);
                else
                {
                    string text = args[i] as string;
                    if (text == null) throw new VireError("foreign needs whole numbers or text", line, col);
                    slot = PinUtf8(text, pins, ref pinsUsed, line, col);
                }
                if (i == 0) a0 = slot;
                else if (i == 1) a1 = slot;
                else if (i == 2) a2 = slot;
                else a3 = slot;
            }
            if (!asText) return CallInt(proc, args.Length, a0, a1, a2, a3);
            return ReadUtf8(CallText(proc, args.Length, a0, a1, a2, a3), line, col);
        }
        finally
        {
            for (int i = 0; i < pinsUsed; i++) pins[i].Free();
            if (!already) CloseModule(module);
        }
    }

    static IntPtr PinUtf8(string text, GCHandle[] pins, ref int pinsUsed, int line, int col)
    {
        if (text.IndexOf('\0') >= 0)
            throw new VireError("foreign text cannot contain a zero", line, col);
        int bytes = Encoding.UTF8.GetByteCount(text);
        if (bytes > MaxForeignText)
            throw new VireError("foreign text is too long", line, col);
        byte[] buf = new byte[bytes + 1];
        Encoding.UTF8.GetBytes(text, 0, text.Length, buf, 0);
        GCHandle pin = GCHandle.Alloc(buf, GCHandleType.Pinned);
        pins[pinsUsed] = pin;
        pinsUsed++;
        return pin.AddrOfPinnedObject();
    }

    static string ReadUtf8(IntPtr ptr, int line, int col)
    {
        if (ptr == IntPtr.Zero) throw new VireError("foreign returned no text", line, col);
        int n = 0;
        while (n <= MaxForeignText)
        {
            if (Marshal.ReadByte(ptr, n) == 0) break;
            n++;
        }
        if (n > MaxForeignText) throw new VireError("foreign text is too long", line, col);
        if (n == 0) return "";
        byte[] buf = new byte[n];
        Marshal.Copy(ptr, buf, 0, n);
        return Encoding.UTF8.GetString(buf);
    }

    static void CloseModule(IntPtr module)
    {
        if (module == IntPtr.Zero) return;
        if (OperatingSystem.IsWindows()) FreeLibrary(module);
        else NativeLibrary.Free(module);
    }

    static int CallInt(IntPtr proc, int count, IntPtr a0, IntPtr a1, IntPtr a2, IntPtr a3)
    {
        if (OperatingSystem.IsWindows())
        {
            if (count == 0) return Marshal.GetDelegateForFunctionPointer<ForeignInt>(proc)();
            if (count == 1) return Marshal.GetDelegateForFunctionPointer<ForeignSlot1>(proc)(a0);
            if (count == 2) return Marshal.GetDelegateForFunctionPointer<ForeignSlot2>(proc)(a0, a1);
            if (count == 3) return Marshal.GetDelegateForFunctionPointer<ForeignSlot3>(proc)(a0, a1, a2);
            return Marshal.GetDelegateForFunctionPointer<ForeignSlot4>(proc)(a0, a1, a2, a3);
        }
        if (count == 0) return Marshal.GetDelegateForFunctionPointer<UnixInt>(proc)();
        if (count == 1) return Marshal.GetDelegateForFunctionPointer<UnixSlot1>(proc)(a0);
        if (count == 2) return Marshal.GetDelegateForFunctionPointer<UnixSlot2>(proc)(a0, a1);
        if (count == 3) return Marshal.GetDelegateForFunctionPointer<UnixSlot3>(proc)(a0, a1, a2);
        return Marshal.GetDelegateForFunctionPointer<UnixSlot4>(proc)(a0, a1, a2, a3);
    }

    static IntPtr CallText(IntPtr proc, int count, IntPtr a0, IntPtr a1, IntPtr a2, IntPtr a3)
    {
        if (OperatingSystem.IsWindows())
        {
            if (count == 0) return Marshal.GetDelegateForFunctionPointer<ForeignText0>(proc)();
            if (count == 1) return Marshal.GetDelegateForFunctionPointer<ForeignText1>(proc)(a0);
            if (count == 2) return Marshal.GetDelegateForFunctionPointer<ForeignText2>(proc)(a0, a1);
            if (count == 3) return Marshal.GetDelegateForFunctionPointer<ForeignText3>(proc)(a0, a1, a2);
            return Marshal.GetDelegateForFunctionPointer<ForeignText4>(proc)(a0, a1, a2, a3);
        }
        if (count == 0) return Marshal.GetDelegateForFunctionPointer<UnixText0>(proc)();
        if (count == 1) return Marshal.GetDelegateForFunctionPointer<UnixText1>(proc)(a0);
        if (count == 2) return Marshal.GetDelegateForFunctionPointer<UnixText2>(proc)(a0, a1);
        if (count == 3) return Marshal.GetDelegateForFunctionPointer<UnixText3>(proc)(a0, a1, a2);
        return Marshal.GetDelegateForFunctionPointer<UnixText4>(proc)(a0, a1, a2, a3);
    }

    static IntPtr LoadExport(string root, object dllValue, object exportValue, int line, int col, out IntPtr module, out bool already)
    {
        module = IntPtr.Zero;
        already = false;
        string dll = dllValue as string;
        string export = exportValue as string;
        if (dll == null || export == null)
            throw new VireError("foreign needs two texts", line, col);
        if (!ExportOk(export))
            throw new VireError("foreign needs an export name", line, col);
        if (!dll.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
            throw new VireError("foreign needs a dll in this folder", line, col);
        if (dll.IndexOf("://", StringComparison.OrdinalIgnoreCase) >= 0)
            throw new VireError("files stay inside the program folder", line, col);
        string full = VirePaths.CombineUnder(root, dll, line, col);
        if (VirePaths.UnderWritableZone(root, full))
            throw new VireError("foreign stays out of data and site", line, col);
        if (UnderSystem(full))
            throw new VireError("files stay inside the program folder", line, col);
        VirePaths.RefuseFileReparse(full, root, line, col);
        if (!File.Exists(full))
            throw new VireError("there is no file by that name", line, col);
        if (OperatingSystem.IsWindows())
        {
            string leaf = Path.GetFileName(full);
            already = GetModuleHandleW(leaf) != IntPtr.Zero || GetModuleHandleW(full) != IntPtr.Zero;
            module = LoadLibraryExW(full, IntPtr.Zero, SearchFlags);
            if (module == IntPtr.Zero)
                throw new VireError("could not open that dll", line, col);
            IntPtr proc = GetProcAddress(module, export);
            if (proc == IntPtr.Zero)
            {
                if (!already) FreeLibrary(module);
                module = IntPtr.Zero;
                throw new VireError("there is no export by that name", line, col);
            }
            return proc;
        }
        try
        {
            module = NativeLibrary.Load(full);
        }
        catch (Exception)
        {
            throw new VireError("could not open that dll", line, col);
        }
        IntPtr unixProc;
        try
        {
            unixProc = NativeLibrary.GetExport(module, export);
        }
        catch (Exception)
        {
            NativeLibrary.Free(module);
            module = IntPtr.Zero;
            throw new VireError("there is no export by that name", line, col);
        }
        return unixProc;
    }

    static bool ExportOk(string name)
    {
        if (name.Length == 0 || name.Length > 64) return false;
        char first = name[0];
        if (!Letter(first) && first != '_') return false;
        for (int i = 1; i < name.Length; i++)
        {
            char ch = name[i];
            if (Letter(ch) || (ch >= '0' && ch <= '9') || ch == '_') continue;
            return false;
        }
        return true;
    }

    static bool Letter(char ch)
    {
        return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
    }

    static bool UnderSystem(string full)
    {
        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (windows.Length > 0 && VirePaths.InFolder(windows, full)) return true;
        string system = Environment.SystemDirectory;
        return system.Length > 0 && VirePaths.InFolder(system, full);
    }

    // Winapi: stdcall on x86, Microsoft x64 on x64. Slots are int or const char* UTF-8.
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int ForeignInt();

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int ForeignSlot1(IntPtr a);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int ForeignSlot2(IntPtr a, IntPtr b);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int ForeignSlot3(IntPtr a, IntPtr b, IntPtr c);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int ForeignSlot4(IntPtr a, IntPtr b, IntPtr c, IntPtr d);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate IntPtr ForeignText0();

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate IntPtr ForeignText1(IntPtr a);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate IntPtr ForeignText2(IntPtr a, IntPtr b);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate IntPtr ForeignText3(IntPtr a, IntPtr b, IntPtr c);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate IntPtr ForeignText4(IntPtr a, IntPtr b, IntPtr c, IntPtr d);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr GetModuleHandleW(string name);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr LoadLibraryExW(string name, IntPtr file, uint flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    static extern IntPtr GetProcAddress(IntPtr module, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool FreeLibrary(IntPtr module);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int UnixInt();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int UnixSlot1(IntPtr a);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int UnixSlot2(IntPtr a, IntPtr b);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int UnixSlot3(IntPtr a, IntPtr b, IntPtr c);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int UnixSlot4(IntPtr a, IntPtr b, IntPtr c, IntPtr d);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate IntPtr UnixText0();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate IntPtr UnixText1(IntPtr a);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate IntPtr UnixText2(IntPtr a, IntPtr b);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate IntPtr UnixText3(IntPtr a, IntPtr b, IntPtr c);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate IntPtr UnixText4(IntPtr a, IntPtr b, IntPtr c, IntPtr d);
}
