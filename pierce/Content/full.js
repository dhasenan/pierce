view = {
  initialize: function() {
    // Set up main layout.
    $.layout.defaults.stateManagement = {
      enabled: true,
      autoSave: true,
      autoLoad: true,
      stateKeys: 'north.size,south.size,east.size,west.size,',
      cookie: {
        expires: 365
      }
    };
    
    // This is currently using the jquery ui layout plugin.
    // I have some annoyances with it. Consider switching to something better,
    // or at least simpler, like http://www.methvin.com/splitter/
    $('#mainPanel').layout({
      defaults: {
        applyDefaultStyles: false,
        resizable: true,
        closable: false,
        slidable: true,
        contentSelector: '.content',
        spacing_open: 4,
        spacing_closed: 4
      },
      west: {
        paneSelector: '.feedList'
      },
      center: {
        paneSelector: '#mainPanelCenter',
        childOptions: {
          center: {
            paneSelector: '#articleList'
          },
          south: {
            paneSelector: '#articleView'
          }
        }
      }
    });
  },

  showUpdateFeedWindow: function(feed, sub) {
    $('#modFeedUrl').val(feed.Uri);
    $('#modFeedTitle').val(feed.Title);
    $('#modFeedInterval').val((sub.CheckInterval / 60) | 0);
    if (sub.Labels) {
      $('#modFeedLabels').val(sub.Labels.join(', '));
    }
    ui.showingPopup = true;
    $('#modifyFeedWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        {
          text: 'Save',
          click: function() {
            var title = $('#modFeedTitle').val();
            var checkInterval = $('#modFeedInterval').val();
            var labels = $('#modFeedLabels').val();
            domain.modifyFeed(feed.Id, title, checkInterval, labels);
          }
        },
        {
          text: 'Unsubscribe',
          click: function() {
            var reallyUnsubscribe = confirm(
                'Are you sure you want to unsubscribe from ' + feed.Title + '?');
            if (reallyUnsubscribe) {
              domain.unsubscribe(feed.Id);
            } else {
              $('#modifyFeedWindow').dialog('close');
            }
          }
        },
        {
          text: 'Refresh',
          click: function() {
            domain.refreshFeed(feed.Id);
            $('#modifyFeedWindow').dialog('close');
          }
        },
      ]
    });
  },

  closeModifyFeedWindow: function() {
    $('#modifyFeedWindow').dialog('close');
  },

  closeFeedWindow: function() {
    $('#addFeedWindow').dialog('close');
  },

  showSettingsWindow: function() {
    ui.showingPopup = true;
    $('#settingsEmail').val(user.Email);
    $('#settingsCurrPassword').val('');
    $('#settingsPassword').val('');
    $('#settingsPasswordConf').val('');
    $('#settingsWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        {
          text: 'Okay go!',
          click: function() {
            ui.applyUserSettings();
          }
        },
      ]
    });
  },

  closeSettingsWindow: function() {
    $('#settingsWindow').dialog('close');
  },

  showAddFeedWindow: function() {
    $('#multifeed').hide();
    $('#addFeedUrl').val('');
    $('#addFeedTitle').val('');
    $('#addFeedLabels').val('');
    ui.showingPopup = true;
    $('#addFeedWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        { text: 'Add feed!', click: ui.addFeed },
      ]
    });
  },

  showLoginWindow: function() {
    ui.showingPopup = true;
    $('#loginWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        {
          text: 'Log in',
          click: function() {
            $.ajax('/Users/Login', {
              dataType: 'json',
              data: {
                'email': $('#email').val(),
                'password': $('#password').val(),
              },
              success: function(data, statusText, xhr) {
                view.hideLoginWindow();
                user = data;
                ui.updateUserInfos();
                domain.refreshFeeds();
              }
            });
          }
        },
        {
          text: 'Register',
          click: function() {
            $.ajax('/Users/Register', {
              dataType: 'json',
              data: {
                'email': $('#email').val(),
                'password': $('#password').val(),
              },
              success: function(data, statusText, xhr) {
                ui.hideLoginWindow();
                user = data;
                ui.updateUserInfos();
                domain.refreshFeeds();
              }
            });
          }
        },
      ]
    });
  },

  hideLoginWindow: function() {
    $('#loginWindow').dialog('close');
  },


  _barrier: null
};
