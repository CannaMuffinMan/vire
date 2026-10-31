using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using Xunit;

public class WinFormsTests
{
    [Fact]
    public void OpenLineFieldButtonSheetCreateARealFormWithoutShowLoop()
    {
        Exception failure = null;
        Thread thread = new Thread(() =>
        {
            try
            {
                string dir = Path.Combine(Path.GetTempPath(), "vire-win-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(dir);
                string path = Path.Combine(dir, "win.vire");
                File.WriteAllText(path, string.Join("\n", new string[]
                {
                    "define tapped",
                    "end",
                    "define main",
                    "  open with \"box\"",
                    "  line with \"hello\"",
                    "  field with \"name\"",
                    "  button with \"go\", \"tapped\"",
                    "  sheet with 40, 20",
                    "  ink with 1, 2, 3",
                    "  fill with 4, 5, 6, 7",
                    "end",
                    ""
                }));
                Dictionary<string, Func> funcs = Program.Load(path, dir, new HashSet<string>());
                Machine machine = new Machine(funcs, dir);
                machine.UseBudget(500000);
                machine.Call("main", new List<object>(), 1);
                Form form = machine.WindowForm;
                Assert.NotNull(form);
                Assert.Equal("box", form.Text);
                Assert.True(form.Controls.Count >= 3);
                form.Close();
                form.Dispose();
            }
            catch (Exception ex)
            {
                failure = ex;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(30000), "WinForms fixture timed out");
        if (failure != null) throw failure;
    }
}
