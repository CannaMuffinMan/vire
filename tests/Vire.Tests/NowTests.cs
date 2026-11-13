using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class NowTests
{
    [Fact]
    public void TicksAreWholeNumbersThatDoNotGoBackwards()
    {
        string src = "can clock\ndefine main\n  let first be ticks\n  let second be ticks\n  return [first, second]\nend\n";
        string dir = Path.Combine(Path.GetTempPath(), "vire-ticks-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "prog.vire");
            File.WriteAllText(path, src);
            Dictionary<string, Func> funcs = Program.Load(path, dir, new HashSet<string>());
            Machine machine = new Machine(funcs, dir);
            object got = machine.Call("main", new List<object>(), 1);
            List<object> pair = Assert.IsType<List<object>>(got);
            Assert.Equal(2, pair.Count);
            int first = Assert.IsType<int>(pair[0]);
            int second = Assert.IsType<int>(pair[1]);
            Assert.True(first > 0);
            Assert.True(second > 0);
            Assert.True(second >= first);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
