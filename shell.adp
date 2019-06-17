<!DOCTYPE html>
<%
   set host [lindex [split [ns_conn location] "/"] 2]
   set wsProtocol [expr {[ns_conn protocol] eq "http" ? "ws" : "wss"}]
   set shellUrl [string map {"/" ""} [ns_config ns/server/[ns_info server]/module/websocket/shell urls]]
   set baseUrl [string trimright $host/$shellUrl]
   set wsUri $wsProtocol://$baseUrl/connect

   # Generate kernelID
   set kernelID [ns_uuid]
   # If kernel is specified
   if {[lindex [split [string map [list /$shellUrl ""] [ns_conn url]] /] 1] eq "kernel"} {
    set kernelID [string trim [string map [list /$shellUrl/kernel ""] [ns_conn url]] "/"]
    # KernelID cannot empty
    if {[string trim $kernelID] eq ""} {
      ns_returnredirect [ns_conn location]/$shellUrl
    }
   } else {
    ns_returnredirect [ns_conn location]/$shellUrl/kernel/$kernelID 
   }

   # Set ns_conn global variable for this kernel
   set conn_commands [list acceptedcompression auth authpassword authuser contentfile contentlength contentsentlength driver files flags form headers host id isconnected location method outputheaders peeraddr peerport pool port protocol query partialtimes request server sock start timeout url urlc urlv version zipaccepted]
   foreach command $conn_commands {
      nsv_set shell_conn $kernelID,$command [ns_conn $command]
   }
 %>
<html>

<head>
  <title>NaviServer shell</title>
  <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css"
    crossorigin="anonymous">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.4.1/css/jquery.terminal.min.css"
    rel="stylesheet" />
  <link href="https://unpkg.com/prismjs@1.16.0/themes/prism-tomorrow.css" rel="stylesheet" />
  <script src="https://code.jquery.com/jquery-3.3.1.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js" crossorigin="anonymous">
  </script>
  <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js" crossorigin="anonymous"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.6.3/js/jquery.terminal.min.js"></script>
  <script src="https://unpkg.com/prismjs@1.16.0/prism.js"></script>
  <script src="https://unpkg.com/prismjs@1.16.0/components/prism-tcl.js"></script>
  <script src="https://unpkg.com/jquery.terminal@2.6.3/js/prism.js"></script>
  <style>
    #autocomplete {
      list-style: none;
      margin: 0;
      padding: 0;
      float: left;
      position: absolute;
      top: 14px;
      left: 0;
      color: #555555;
    }
  </style>
</head>

<body role="document" class="bg-black h-100 w-100">

  <div id="term_demo" class="w-100 h-100"></div>
  <script language="javascript" type="text/javascript">
    var wsUri = '<%= $wsUri %>';
    var kernelID = '<%= $kernelID %>';
    var kernelName = "user-" + kernelID.substring(0, 5).toLowerCase();
    var output;
    var state;
    var websocket = 0;
    var myterm = null;
    var autocomplete_options = null;
    var wrapper = null;
    var keywords = [];
    var original_keywords = Prism.languages.tcl.keyword;

    function init() {
      initializeTerminal();
      testWebSocket();
    }

    function initializeTerminal() {
      jQuery(function ($, undefined) {
        $('#term_demo').terminal(function (command, term) {
          myterm = term;
          var kernel = kernelID;
          if (kernel === undefined) {
            kernel = '';
          }
          command = command.trimLeft();
          if (command !== '') {
            websocket.send(JSON.stringify(['eval', command, kernel]));
          } else {
            term.echo('');
          }
        }, {
          greetings: function () {
            this.echo('[[;white;]##################################]');
            this.echo('[[;white;]#  Welcome to naviserver shell.  #]');
            this.echo('[[;white;]##################################]');
            myterm = this;
          },
          onInit: function (term) {
            // Get wrapper from terminal
            wrapper = term.cmd().find('.cursor').wrap('<span/>').parent().addClass('cmd-wrapper');
            // Add autocomplete span to wrapper
            $("<span id='autocomplete'></span>").appendTo(wrapper);
          },
          name: kernelName,
          prompt: "[[;yellow;]" + kernelName + "]" + "$ ",
          keydown: function (e) {
            // If Tab, autocomplete
            if (e.key == "Tab") {
              // Auto add ::
              /*
              var is_namespace = true;
              autocomplete_options.forEach(function (item) {
                if (item.charAt(0) != ":") {
                  is_namespace = false;
                }
              });
              if (is_namespace && myterm.get_command().trimLeft().charAt(0) != ":")
                myterm.set_command("::" + myterm.get_command().trimLeft());
              */
              // Auto complete
              myterm.complete(autocomplete_options);
              return false;
            }
          },
          onCommandChange: function (command, term) {
            // Show autocomplete options when command change
            //subcommand = command.split("[");
            //command = subcommand[subcommand.length-1];
            // Trim whitespace
            command = command.trimLeft();
            // If command is blank, not run autocomplete & hide current option
            if (command.trim() != "")
              // Get autocomplete options via websocket, look at function update_autocomplete()
              websocket.send(JSON.stringify(['autocomplete', command, kernelID]));
            else
              update_autocomplete("");
          }
        });
        // Syntax Highlight
        $.terminal.defaults.formatters.push(function (string) {
          // After execute, command will start with "$ "
          // Therefore, extract the prefix
          var prefix = "";
          if(string.split(" ")[0] == "$"){
            prefix = "$ ";
            var s = string.split(" ");
            s.shift();
            string = s.join(" ");
          }
          // Highlight command
          console.log($.terminal.prism("tcl",$.terminal.escape_brackets(string)));
          return prefix+$.terminal.prism("tcl",$.terminal.escape_brackets(string));
        });
      });
    }

    function testWebSocket() {
      if ("WebSocket" in window) {
        websocket = new WebSocket(wsUri);
      } else {
        websocket = new MozWebSocket(wsUri);
      }
      websocket.onopen = function (evt) {
        onOpen(evt)
      };
      websocket.onclose = function (evt) {
        onClose(evt)
      };
      websocket.onmessage = function (evt) {
        onMessage(evt)
      };
      websocket.onerror = function (evt) {
        onError(evt)
      };
    }

    function onOpen(evt) {
      myterm.echo('[[;lightgreen;]Kernel "' + kernelName + '" is connected.]');
      heartbeat();
    }

    function onClose(evt) {
      myterm.echo('[[;red;]Kernel "' + kernelName + '" is disconnected.]');
      testWebSocket();
    }

    function onMessage(evt) {
      if (evt.data == "") return;
      var result = window.eval(evt.data.split("\n").join("\\n"));
      $('html, body').scrollTop($(document).height());
    }

    function onError(evt) {}

    function doSend(message) {
      websocket.send(message);
    }

    function checkSubmit(e) {
      if (e && e.keyCode == 13) {
        doSend($('#msg').val());
      }
    }

    function clearOutput() {
      myterm.clear();
    }

    function update_autocomplete(text) {
      if (myterm == null) return;
      // Update options array
      autocomplete_options = text.split(" ");
      var type = autocomplete_options.shift();
      // Add commands to keywords for highlighting
      if(type == "commands"){
        keywords = keywords.concat(autocomplete_options).filter(unique);
        updateKeywords();
      }
      // Add '[' if nessessary
      if (myterm.get_command().trim().split(" ").pop().charAt(0) == '[') {
        for (var i = 0; i < autocomplete_options.length; i++)
          autocomplete_options[i] = "[" + autocomplete_options[i];
      }
      // If there is any option, show options
      if (autocomplete_options.length > 0 &&
        myterm.get_command().trim().split(" ").pop() != autocomplete_options.join(" ") &&
        myterm.get_command().trim() != "") {
        $("#autocomplete").html(autocomplete_options.join(" "));
      } else {
        $("#autocomplete").html("");
      }
    }

    function updateKeywords(){
      var new_source = original_keywords.pattern.source;
      var index = new_source.indexOf("vwait");
      new_source = new_source.substring(0,index) + keywords.join("|") + "|" + new_source.substring(index);
      Prism.languages.tcl = Prism.languages.extend('tcl', { 'keyword': {
        lookbehind: true,
        pattern: new RegExp(new_source, "m")
      }});
    }

    function unique(value, index, self) {
      return self.indexOf(value) === index;
    }

    function heartbeat() {
      websocket.send(JSON.stringify(['heartbeat', kernelID]));
      // Send heartbeat every 3s
      setTimeout(function () {
        heartbeat();
      }, "<%= $::ws::shell::shell_heartbeat %>" );
    }

    $(document).ready(function () {
      init()
    });
  </script>
</body>

</html>