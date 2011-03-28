﻿<%@ Page Title="" Language="C#" MasterPageFile="~/Views/Shared/Site.Master" Inherits="System.Web.Mvc.ViewPage<AddNewSeriesModel>" %>

<%@ Import Namespace="NzbDrone.Web.Models" %>
<%@ Import Namespace="Telerik.Web.Mvc.UI" %>
<%@ Import Namespace="NzbDrone.Core.Repository" %>
<asp:Content ID="Content1" ContentPlaceHolderID="TitleContent" runat="server">
    Add New Series
    <script type="text/javascript">
        jQuery(document).ready(function () {
            $('#searchButton').attr('disabled', '');
        });
    </script>
</asp:Content>
<asp:Content ID="Menu" ContentPlaceHolderID="ActionMenu" runat="server">
    <%
        Html.RenderPartial("SubMenu");
    %>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="MainContent" runat="server">
    <div style="width: 60%">
        <div style="display: inline">
            <%= Html.Label("Enter a Series Name") %>
            <%= Html.TextBox("new_series_name", String.Empty, new { id="new_series_id" }) %>
            <button class="t.button" id="searchButton" disabled="disabled" onclick="searchSeries ()">
                Search</button>
        </div>
        <div style="display: inline; float: right;">
            <%= Html.LabelFor(m => m.QualityProfileId)%>
            <%: Html.DropDownListFor(m => m.QualityProfileId, Model.QualitySelectList)%>
        </div>
    </div>
    <div id="result">
    </div>
    <div id="RootDirectories" class="rootDirectories" style="display: none">
        <fieldset>
            <legend>Root TV Folders</legend>
            <% int d = 0; %>
            <% foreach (var dir in Model.RootDirectories)
               { %>
            <%: Html.RadioButton("selectedRootDir", dir.Path, d ==0 , new { @class="dirList examplePart", id="dirRadio_" + d }) %>
            <%: Html.Label(dir.Path) %>
            <% } %>
        </fieldset>
        <div id="example">
        </div>
        <button class="t.button" onclick="addSeries ()">
            Add New Series</button>
    </div>
    <div id="addResult">
    </div>
    <script type="text/javascript" language="javascript">

        $('#new_series_id').bind('keydown', function (e) {
            if (e.keyCode == 13) {
                $('#searchButton').click();
            }
        });

        function searchSeries() {
            var seriesSearch = $('#new_series_id');

            $("#result").text("Searching...");
            document.getElementById('RootDirectories').style.display = 'inline';
            $("#result").load('<%=Url.Action("SearchForSeries", "Series") %>', {
                seriesName: seriesSearch.val()
            });
        }
         
        function addSeries() {
            //Get the selected tvdbid + selected root folder
            //jquery bit below doesn't want to work...

            var checkedSeries = $("input[name='selectedSeries']:checked").val();
            //var checkedSeries = $('input.searchRadio:checked').val();
            //var checkedSeries = $('input:radio[name=selectedSeries]:checked').val();
            //var checkedSeries = $('input:radio[class=searchRadio]:checked').val();

            var checkedDir = $("input[name='selectedRootDir']:checked").val();

            var id = "#" + checkedSeries + "_text";
            var seriesName = $(id).val();
            var qualityProfileId = $("#QualityProfileId").val();

            $("#addResult").load('<%=Url.Action("AddNewSeries", "Series") %>', {
                dir: checkedDir,
                seriesId: checkedSeries,
                seriesName: seriesName,
                qualityProfileId: qualityProfileId
            });
        }

        //Need to figure out how to use 'ViewData["DirSep"]' instead of hardcoding '\'
        $(".examplePart").live("change", function () {
            var dir = $("input[name='selectedRootDir']:checked").val();
            var series = $("input[name='selectedSeries']:checked").val();

            var id = "#" + series + "_text";
            var seriesName = $(id).val();

            var sep = "\\";

            var str = "Target: " + dir + sep + seriesName;

            $('#example').text(str);

        });
    </script>
    <div id="tester">
    </div>
</asp:Content>
