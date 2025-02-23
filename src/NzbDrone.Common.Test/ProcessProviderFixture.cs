﻿using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using FluentAssertions;
using NUnit.Framework;
using NzbDrone.Common.Model;
using NzbDrone.Common.Processes;
using NzbDrone.Test.Common;
using NzbDrone.Test.Dummy;

namespace NzbDrone.Common.Test
{
    // We don't want one tests setup killing processes used in another
    [NonParallelizable]
    [TestFixture]
    public class ProcessProviderFixture : TestBase<ProcessProvider>
    {

        [SetUp]
        public void Setup()
        {
            Process.GetProcessesByName(DummyApp.DUMMY_PROCCESS_NAME).ToList().ForEach(c =>
                {
                    c.Kill();
                    c.WaitForExit();
                });

            Process.GetProcessesByName(DummyApp.DUMMY_PROCCESS_NAME).Should().BeEmpty();
        }

        [TearDown]
        public void TearDown()
        {
            Process.GetProcessesByName(DummyApp.DUMMY_PROCCESS_NAME).ToList().ForEach(c =>
            {
                try
                {
                    c.Kill();
                }
                catch (Win32Exception ex)
                {
                    TestLogger.Warn(ex, "{0} when killing process", ex.Message);
                }
                
            });
        }

        [Test]
        public void GetById_should_return_null_if_process_doesnt_exist()
        {
            Subject.GetProcessById(1234567).Should().BeNull();

            ExceptionVerification.ExpectedWarns(1);
        }

        [TestCase(0)]
        [TestCase(-1)]
        [TestCase(9999)]
        public void GetProcessById_should_return_null_for_invalid_process(int processId)
        {
            Subject.GetProcessById(processId).Should().BeNull();

            ExceptionVerification.ExpectedWarns(1);
        }

        [Test]
        public void should_be_able_to_start_process()
        {
            var process = StartDummyProcess();

            var check = Subject.GetProcessById(process.Id);
            check.Should().NotBeNull();

            process.Refresh();
            process.HasExited.Should().BeFalse();

            process.Kill();
            process.WaitForExit();
            process.HasExited.Should().BeTrue();
        }

        [Test]
        [Platform(Exclude="MacOsX")]
        [Retry(3)]
        public void exists_should_find_running_process()
        {
            var process = StartDummyProcess();

            Subject.Exists(DummyApp.DUMMY_PROCCESS_NAME).Should()
                   .BeTrue("expected one dummy process to be already running");

            process.Kill();
            process.WaitForExit();

            Subject.Exists(DummyApp.DUMMY_PROCCESS_NAME).Should().BeFalse();
        }


        [Test]
        [Platform(Exclude="MacOsX")]
        public void kill_all_should_kill_all_process_with_name()
        {
            var dummy1 = StartDummyProcess();
            var dummy2 = StartDummyProcess();

            Subject.KillAll(DummyApp.DUMMY_PROCCESS_NAME);

            dummy1.HasExited.Should().BeTrue();
            dummy2.HasExited.Should().BeTrue();
        }

        private Process StartDummyProcess()
        {
            var processStarted = new ManualResetEventSlim();

            var path = Path.Combine(TestContext.CurrentContext.TestDirectory, DummyApp.DUMMY_PROCCESS_NAME + ".exe");
            var process = Subject.Start(path, onOutputDataReceived: (string data) => {
                    if (data.StartsWith("Dummy process. ID:"))
                    {
                        processStarted.Set();
                    }
                });

            if (!processStarted.Wait(2000))
            {
                Assert.Fail("Failed to start process within 2 sec");
            }

            return process;
        }

        [Test]
        [Retry(3)]
        public void ToString_on_new_processInfo()
        {
            Console.WriteLine(new ProcessInfo().ToString());
            ExceptionVerification.MarkInconclusive(typeof(Win32Exception));
        }
    }
}
