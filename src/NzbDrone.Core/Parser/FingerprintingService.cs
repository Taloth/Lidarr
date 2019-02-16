using System.IO;
using NLog;
using NzbDrone.Core.Parser.Model;
using System.Diagnostics;
using System.Linq;
using NzbDrone.Common.Http;
using NzbDrone.Common.Extensions;
using System.Collections.Generic;
using System.IO.Compression;
using System.Text;
using NzbDrone.Common.Serializer;
using System;
using NzbDrone.Common.EnvironmentInfo;
using System.Threading;
using System.Text.RegularExpressions;

namespace NzbDrone.Core.Parser
{
    public interface IFingerprintingService
    {
        bool IsSetup();
        Version FpcalcVersion();
        void Lookup(List<LocalTrack> tracks, double threshold);
    }

    public class AcoustId
    {
        public double Duration { get; set; }
        public string Fingerprint { get; set; }
    }

    public class FingerprintingService : IFingerprintingService
    {
        private const string _acoustIdUrl = "https://api.acoustid.org/v2/lookup";
        private const string _acoustIdApiKey = "QANd68ji1L";
        private const int _fingerprintingTimeout = 10000;
        
        private readonly Logger _logger;
        private readonly IHttpClient _httpClient;
        private readonly IHttpRequestBuilderFactory _customerRequestBuilder;
        
        private readonly string _fpcalcPath;
        private readonly Version _fpcalcVersion;
        private readonly string _fpcalcArgs;

        public FingerprintingService(Logger logger,
                                     IHttpClient httpClient)
        {
            _logger = logger;
            _httpClient = httpClient;

            _customerRequestBuilder = new HttpRequestBuilder(_acoustIdUrl).CreateFactory();

            _fpcalcPath = GetFpcalcPath();
            if (_fpcalcPath.IsNotNullOrWhiteSpace())
            {
                _fpcalcVersion = GetFpcalcVersion();
                _fpcalcArgs = GetFpcalcArgs();
            }
        }

        public bool IsSetup() => _fpcalcPath.IsNotNullOrWhiteSpace();
        public Version FpcalcVersion() => _fpcalcVersion;

        private string GetFpcalcPath()
        {
            string path = null;
            if (OsInfo.IsLinux)
            {
                // must be on users path on Linux
                path = "fpcalc";

                // check that the command exists
                Process p = new Process();
                p.StartInfo.FileName = "which";
                p.StartInfo.Arguments = $"{path}";
                p.StartInfo.UseShellExecute = false;
                p.StartInfo.RedirectStandardOutput = true;

                p.Start();
                // To avoid deadlocks, always read the output stream first and then wait.  
                string output = p.StandardOutput.ReadToEnd();  
                p.WaitForExit(1000);

                if (p.ExitCode != 0)
                {
                    _logger.Debug("fpcalc not found");
                    return null;
                }
            }
            else
            {
                // on OSX / Windows, we have put fpcalc in the application folder
                path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "fpcalc");
                if (OsInfo.IsWindows)
                {
                    path += ".exe";
                }

                if (!File.Exists(path))
                {
                    _logger.Warn("fpcalc missing from application directory");
                    return null;
                }
            }
            
            _logger.Debug($"fpcalc path: {path}");
            return path;
        }

        private Version GetFpcalcVersion()
        {
            if (_fpcalcPath == null)
            {
                return null;
            }

            Process p = new Process();
            p.StartInfo.FileName = _fpcalcPath;
            p.StartInfo.Arguments = $"-version";
            p.StartInfo.UseShellExecute = false;
            p.StartInfo.RedirectStandardOutput = true;

            p.Start();
            // To avoid deadlocks, always read the output stream first and then wait.
            string output = p.StandardOutput.ReadToEnd();
            p.WaitForExit(1000);

            if (p.ExitCode != 0)
            {
                _logger.Warn("Could not get fpcalc version (may be known issue with fpcalc v1.4)");
                return null;
            }

            var versionstring = Regex.Match(output, @"\d\.\d\.\d").Value;
            if (versionstring.IsNullOrWhiteSpace())
            {
                return null;
            }

            var version = new Version(versionstring);
            _logger.Debug($"fpcalc version: {version}");

            return version;
        }

        private string GetFpcalcArgs()
        {
            var args = "";

            if (_fpcalcVersion == null)
            {
                return args;
            }

            if (_fpcalcVersion >= new Version("1.4.0"))
            {
                args = "-json";
            }
            
            if (_fpcalcVersion >= new Version("1.4.3"))
            {
                args += " -ignore-errors";
            }

            return args;
        }

        public AcoustId ParseFpcalcJsonOutput(string output)
        {
             return Json.Deserialize<AcoustId>(output);
        }

        public AcoustId ParseFpcalcTextOutput(string output)
        {
                var durationstring = Regex.Match(output, @"(?<=DURATION=)[\d\.]+(?=\s)").Value;
                double duration;
                if (durationstring.IsNullOrWhiteSpace() || !double.TryParse(durationstring, out duration))
                {
                    return null;
                }

                var fingerprint = Regex.Match(output, @"(?<=FINGERPRINT=)[^\s]+").Value;
                if (fingerprint.IsNullOrWhiteSpace())
                {
                    return null;
                }

                return new AcoustId {
                    Duration = duration,
                    Fingerprint = fingerprint
                };
        }

        public AcoustId ParseFpcalcOutput(string output)
        {
            if (output.IsNullOrWhiteSpace())
            {
                return null;
            }
            
            if (_fpcalcArgs.Contains("-json"))
            {
                return ParseFpcalcJsonOutput(output);
            }
            else
            {
                return ParseFpcalcTextOutput(output);
            }
        }

        public AcoustId GetFingerprint(string file)
        {
            if (IsSetup() && File.Exists(file))
            {
                Process p = new Process();
                p.StartInfo.FileName = _fpcalcPath;
                p.StartInfo.Arguments = $"{_fpcalcArgs} \"{file}\"";
                p.StartInfo.UseShellExecute = false;
                p.StartInfo.RedirectStandardOutput = true;
                p.StartInfo.RedirectStandardError = true;

                _logger.Trace("Executing {0} {1}", p.StartInfo.FileName, p.StartInfo.Arguments);

                StringBuilder output = new StringBuilder();
                StringBuilder error = new StringBuilder();

                // see https://stackoverflow.com/questions/139593/processstartinfo-hanging-on-waitforexit-why?lq=1
                // this is most likely overkill...
                using (AutoResetEvent outputWaitHandle = new AutoResetEvent(false))
                 {
                     using (AutoResetEvent errorWaitHandle = new AutoResetEvent(false))
                     {
                         DataReceivedEventHandler outputHandler = delegate(object sender, DataReceivedEventArgs e)
                             {
                                 if (e.Data == null)
                                 {
                                     outputWaitHandle.Set();
                                 }
                                 else
                                 {
                                     output.AppendLine(e.Data);
                                 }
                             };

                         DataReceivedEventHandler errorHandler = delegate(object sender, DataReceivedEventArgs e)
                             {
                                 if (e.Data == null)
                                 {
                                     errorWaitHandle.Set();
                                 }
                                 else
                                 {
                                     error.AppendLine(e.Data);
                                 }
                             };
                         
                         p.OutputDataReceived += outputHandler;
                         p.ErrorDataReceived += errorHandler;

                         p.Start();

                         p.BeginOutputReadLine();
                         p.BeginErrorReadLine();

                         if (p.WaitForExit(_fingerprintingTimeout) &&
                             outputWaitHandle.WaitOne(_fingerprintingTimeout) &&
                             errorWaitHandle.WaitOne(_fingerprintingTimeout))
                         {
                             // Process completed.
                             if (p.ExitCode != 0)
                             {
                                 _logger.Warn($"fpcalc error: {error}");
                                 return null;
                             }
                             else
                             {
                                 return ParseFpcalcOutput(output.ToString());
                             }
                         }
                         else
                         {
                             // Timed out.  Remove handlers to avoid object disposed error
                             p.OutputDataReceived -= outputHandler;
                             p.ErrorDataReceived -= errorHandler;
                             
                             _logger.Warn($"fpcalc timed out. {error}");
                             return null;
                         }
                     }
                 }
            }

            return null;
        }

        private static byte[] Compress(byte[] data)
        {
            using (var compressedStream = new MemoryStream())
            using (var zipStream = new GZipStream(compressedStream, CompressionMode.Compress))
            {
                zipStream.Write(data, 0, data.Length);
                zipStream.Close();
                return compressedStream.ToArray();
            }
        }

        public void Lookup(List<LocalTrack> tracks, double threshold)
        {
            if (!IsSetup())
            {
                return;
            }
            
            Lookup(tracks.Select(x => Tuple.Create(x, GetFingerprint(x.Path))).ToList(), threshold);
        }

        public void Lookup(List<Tuple<LocalTrack, AcoustId>> files, double threshold)
        {
            var toLookup = files.Where(x => x.Item2 != null).ToList();
            if (!toLookup.Any())
            {
                return;
            }

            var httpRequest = _customerRequestBuilder.Create()
                .WithRateLimit(0.334)
                .Build();

            var sb = new StringBuilder($"client={_acoustIdApiKey}&format=json&meta=recordingids&batch=1", 2000);
            for (int i = 0; i < toLookup.Count; i++)
            {
                sb.Append($"&duration.{i}={toLookup[i].Item2.Duration:F0}&fingerprint.{i}={toLookup[i].Item2.Fingerprint}");
            }
            
            // they prefer a gzipped body
            httpRequest.SetContent(Compress(Encoding.UTF8.GetBytes(sb.ToString())));
            httpRequest.Headers.Add("Content-Encoding", "gzip");
            httpRequest.Headers.ContentType = "application/x-www-form-urlencoded";

            var httpResponse = _httpClient.Post<LookupResponse>(httpRequest);

            if (httpResponse.HasHttpError)
            {
                throw new HttpException(httpRequest, httpResponse);
            }

            var response = httpResponse.Resource;

            if (!string.IsNullOrEmpty(response.ErrorMessage))
            {
                _logger.Debug("Webservice error: {0}", response.ErrorMessage);
                return;
            }

            foreach (var fileResponse in response.Fingerprints)
            {
                if (fileResponse.Results.Count == 0)
                {
                    _logger.Debug("No results for given fingerprint.");
                    continue;
                }

                foreach (var result in fileResponse.Results.Where(x => x.Recordings != null))
                {
                    _logger.Trace("Found: {0}, {1}, {2}", result.Id, result.Score, string.Join(", ", result.Recordings.Select(x => x.Id)));
                }

                var ids = fileResponse.Results.Where(x => x.Score > threshold && x.Recordings != null).SelectMany(y => y.Recordings.Select(z => z.Id)).Distinct().ToList();
                _logger.Trace("All recordings: {0}", string.Join("\n", ids));

                toLookup[fileResponse.index].Item1.AcoustIdResults = ids;
            }

            _logger.Debug("Fingerprinting complete.");
        }

        private class LookupResponse
        {
            public string StatusCode { get; set; }
            public string ErrorMessage { get; set; }
            public List<LookupResultListItem> Fingerprints { get; set; }
        }

        private class LookupResultListItem
        {
            public int index { get; set; }
            public List<LookupResult> Results { get; set; }
        }

        private class LookupResult
        {
            public string Id { get; set; }
            public double Score { get; set; }
            public List<RecordingResult> Recordings { get; set; }
        }

        private class RecordingResult
        {
            public string Id { get; set; }
        }
    }
}
