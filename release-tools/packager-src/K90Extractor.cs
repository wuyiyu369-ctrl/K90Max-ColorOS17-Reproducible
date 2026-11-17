using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace K90Extractor
{
    internal sealed class ExtractForm : Form
    {
        private readonly TextBox pathBox;
        private readonly Button browseButton;
        private readonly Button extractButton;
        private readonly ProgressBar progress;
        private readonly Label status;
        private readonly Label percent;
        private Thread worker;

        public ExtractForm()
        {
            Text = "K90 Max ColorOS 17 一键刷机包";
            ClientSize = new Size(900, 520);
            MinimumSize = new Size(820, 500);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Microsoft YaHei UI", 10F, FontStyle.Regular, GraphicsUnit.Point);
            ForeColor = Color.White;
            BackColor = Color.FromArgb(11, 16, 24);
            DoubleBuffered = true;

            Label title = new Label();
            title.Text = "K90 Max  ·  ColorOS 17";
            title.Font = new Font("Microsoft YaHei UI", 25F, FontStyle.Bold);
            title.AutoSize = true;
            title.BackColor = Color.Transparent;
            title.Location = new Point(54, 48);
            Controls.Add(title);

            Label subtitle = new Label();
            subtitle.Text = "Stage48 中文一键刷机包";
            subtitle.Font = new Font("Microsoft YaHei UI", 13F, FontStyle.Regular);
            subtitle.ForeColor = Color.FromArgb(166, 226, 204);
            subtitle.AutoSize = true;
            subtitle.BackColor = Color.Transparent;
            subtitle.Location = new Point(58, 105);
            Controls.Add(subtitle);

            Label author = new Label();
            author.Text = "作者：哆啦A梦";
            author.AutoSize = true;
            author.ForeColor = Color.FromArgb(185, 194, 207);
            author.BackColor = Color.Transparent;
            author.Location = new Point(59, 145);
            Controls.Add(author);

            Label hint = new Label();
            hint.Text = "请选择解压目录。需要至少 16 GB 可用空间，解压完成后将自动打开中文刷机向导。";
            hint.AutoSize = false;
            hint.Size = new Size(785, 46);
            hint.ForeColor = Color.FromArgb(220, 226, 234);
            hint.BackColor = Color.Transparent;
            hint.Location = new Point(59, 216);
            Controls.Add(hint);

            pathBox = new TextBox();
            pathBox.Location = new Point(59, 270);
            pathBox.Size = new Size(650, 30);
            pathBox.Text = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            Controls.Add(pathBox);

            browseButton = new Button();
            browseButton.Text = "选择目录";
            browseButton.Location = new Point(724, 268);
            browseButton.Size = new Size(118, 34);
            browseButton.Click += delegate { Browse(); };
            Controls.Add(browseButton);

            progress = new ProgressBar();
            progress.Location = new Point(59, 338);
            progress.Size = new Size(650, 22);
            progress.Minimum = 0;
            progress.Maximum = 100;
            Controls.Add(progress);

            percent = new Label();
            percent.Text = "0%";
            percent.Font = new Font("Segoe UI", 11F, FontStyle.Bold);
            percent.AutoSize = true;
            percent.BackColor = Color.Transparent;
            percent.Location = new Point(724, 337);
            Controls.Add(percent);

            status = new Label();
            status.Text = "等待开始";
            status.AutoSize = false;
            status.Size = new Size(650, 42);
            status.ForeColor = Color.FromArgb(185, 194, 207);
            status.BackColor = Color.Transparent;
            status.Location = new Point(59, 374);
            Controls.Add(status);

            extractButton = new Button();
            extractButton.Text = "开始解压";
            extractButton.Font = new Font("Microsoft YaHei UI", 11F, FontStyle.Bold);
            extractButton.Location = new Point(680, 420);
            extractButton.Size = new Size(162, 48);
            extractButton.BackColor = Color.FromArgb(37, 184, 126);
            extractButton.FlatStyle = FlatStyle.Flat;
            extractButton.FlatAppearance.BorderSize = 0;
            extractButton.Click += delegate { StartExtract(); };
            Controls.Add(extractButton);

            Shown += delegate
            {
                string testDestination = Environment.GetEnvironmentVariable("K90_EXTRACT_TEST_DEST");
                if (!String.IsNullOrEmpty(testDestination))
                {
                    pathBox.Text = testDestination;
                    StartExtract();
                }
            };
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (LinearGradientBrush brush = new LinearGradientBrush(
                ClientRectangle,
                Color.FromArgb(10, 15, 23),
                Color.FromArgb(19, 52, 49),
                28F))
            {
                e.Graphics.FillRectangle(brush, ClientRectangle);
            }
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen pen = new Pen(Color.FromArgb(36, 89, 78), 2F))
            {
                e.Graphics.DrawEllipse(pen, ClientSize.Width - 330, -130, 430, 430);
                e.Graphics.DrawEllipse(pen, ClientSize.Width - 240, -40, 260, 260);
            }
            using (SolidBrush glow = new SolidBrush(Color.FromArgb(18, 57, 196, 143)))
            {
                e.Graphics.FillEllipse(glow, ClientSize.Width - 255, -35, 190, 190);
            }
        }

        private void Browse()
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "请选择刷机包解压到哪个目录";
                dialog.SelectedPath = pathBox.Text;
                dialog.ShowNewFolderButton = true;
                if (dialog.ShowDialog(this) == DialogResult.OK)
                    pathBox.Text = dialog.SelectedPath;
            }
        }

        private void StartExtract()
        {
            string destination = pathBox.Text.Trim();
            if (destination.Length == 0)
            {
                MessageBox.Show(this, "请先选择解压目录。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            try
            {
                Directory.CreateDirectory(destination);
                DriveInfo drive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(destination)));
                if (String.IsNullOrEmpty(Environment.GetEnvironmentVariable("K90_EXTRACT_TEST_DEST")) &&
                    drive.AvailableFreeSpace < 16L * 1024L * 1024L * 1024L)
                {
                    DialogResult choice = MessageBox.Show(
                        this,
                        "目标磁盘可用空间低于 16 GB，可能无法完成解压。仍要继续吗？",
                        "空间不足",
                        MessageBoxButtons.YesNo,
                        MessageBoxIcon.Warning);
                    if (choice != DialogResult.Yes) return;
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "无法使用该目录：" + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            pathBox.Enabled = false;
            browseButton.Enabled = false;
            extractButton.Enabled = false;
            status.Text = "正在准备内置解压程序……";
            worker = new Thread(new ThreadStart(delegate { ExtractWorker(destination); }));
            worker.IsBackground = true;
            worker.Start();
        }

        private void ExtractWorker(string destination)
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "K90Extractor_" + Process.GetCurrentProcess().Id.ToString());
            string sevenZip = Path.Combine(tempDir, "7za.exe");
            try
            {
                Directory.CreateDirectory(tempDir);
                using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("K90Extractor.SevenZip"))
                {
                    if (input == null) throw new InvalidOperationException("内置 7-Zip 资源缺失。");
                    using (FileStream output = new FileStream(sevenZip, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        byte[] buffer = new byte[65536];
                        int read;
                        while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                            output.Write(buffer, 0, read);
                    }
                }

                ProcessStartInfo info = new ProcessStartInfo();
                info.FileName = sevenZip;
                info.Arguments = "x -y -aoa -bsp1 -bso1 -bse1 -o\"" + destination.Replace("\"", "\"\"") + "\" \"" +
                    Application.ExecutablePath.Replace("\"", "\"\"") + "\"";
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.RedirectStandardOutput = true;
                info.RedirectStandardError = true;

                Process process = new Process();
                process.StartInfo = info;
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args) { ParseProgress(args.Data); };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args) { ParseProgress(args.Data); };
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                process.WaitForExit();
                if (process.ExitCode != 0)
                    throw new InvalidOperationException("7-Zip 解压失败，退出码：" + process.ExitCode.ToString());

                string[] launchers = Directory.GetFiles(destination, "START_FLASH.cmd", SearchOption.AllDirectories);
                if (launchers.Length != 1)
                    throw new InvalidOperationException("解压后没有找到唯一的 START_FLASH.cmd。");

                SetProgress(100, "解压完成，正在打开中文刷机向导……");
                if (Environment.GetEnvironmentVariable("K90_EXTRACT_NO_LAUNCH") == "1")
                {
                    File.WriteAllText(Path.Combine(destination, "K90_EXTRACT_TEST_OK.txt"), "OK", Encoding.ASCII);
                }
                else
                {
                    ProcessStartInfo launch = new ProcessStartInfo();
                    launch.FileName = launchers[0];
                    launch.WorkingDirectory = Path.GetDirectoryName(launchers[0]);
                    launch.UseShellExecute = true;
                    Process.Start(launch);
                }
                BeginInvoke(new MethodInvoker(delegate { Close(); }));
            }
            catch (Exception ex)
            {
                BeginInvoke(new MethodInvoker(delegate
                {
                    status.Text = "解压失败：" + ex.Message;
                    extractButton.Enabled = true;
                    browseButton.Enabled = true;
                    pathBox.Enabled = true;
                    MessageBox.Show(this, status.Text, "解压失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }));
            }
            finally
            {
                try { if (File.Exists(sevenZip)) File.Delete(sevenZip); } catch { }
                try { if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true); } catch { }
            }
        }

        private void ParseProgress(string line)
        {
            if (String.IsNullOrEmpty(line)) return;
            Match match = Regex.Match(line, @"(\d{1,3})%");
            if (match.Success)
            {
                int value;
                if (Int32.TryParse(match.Groups[1].Value, out value))
                    SetProgress(Math.Max(0, Math.Min(100, value)), "正在解压刷机包，请稍候……");
            }
        }

        private void SetProgress(int value, string text)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new MethodInvoker(delegate { SetProgress(value, text); }));
                return;
            }
            progress.Value = value;
            percent.Text = value.ToString() + "%";
            status.Text = text;
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new ExtractForm());
        }
    }
}
