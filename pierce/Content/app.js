var user;
var feeds;

var bodyLayout;

var domain = {
  getSubscription: function(feedId) {
    if (!user.Subscriptions) return;
    for (var i = 0; i < user.Subscriptions.length; i++) {
      if (user.Subscriptions[i].FeedId == feedId) {
        return user.Subscriptions[i];
      }
    }
    return null;
  },

  getFeed: function(feedId) {
    for (var i = 0; i < feeds.length; i++) {
      if (feeds[i].Id == feedId) {
        return feeds[i];
      }
    }
    return null;
  },

  getArticle: function(feed, artId) {
    for (var i = 0; i < feed.Articles.length; i++) {
      if (feed.Articles[i].HashId == artId) {
        return feed.Articles[i];
      }
    }
    return null;
  },

  articleId: function(feed, article) {
    return 'articleli_' + feed.Id + '_' + article.HashId;
  },

  jsDate: function(aspNetDate) {
    return new Date(parseInt(aspNetDate.substr(6)));
  },

  mungeFeed: function(feed) {
    feed.LastRead = domain.jsDate(feed.LastRead);
    feed.NextRead = domain.jsDate(feed.NextRead);
    feed.ReadInterval = feed.ReadInterval.TotalSeconds;
    var sub = domain.getSubscription(feed.Id);
    if (!sub) {
      console.log('feed ' + feed.Id + ' has no subscription');
      return;
    }
    $.each(feed.Articles, function(i, art) {
      art.PublishDate = domain.jsDate(art.PublishDate);
      art.HashId = util.hashString(art.UniqueId);
      if (sub) {
        art.IsRead = sub.ReadArticles.indexOf(art.UniqueId) >= 0;
      }
    });
  },

  refreshUser: function() {
    $.ajax('/Users/Get', {
      dataType: 'json',
      success: function(data, statusText, xhr) {
        user = data;
        ui.updateUserInfos();
        domain.refreshFeeds();
      },
      error: function() {
        ui.showLoginWindow();
      }
    });
  },

  refreshFeeds: function() {
    $.ajax('/Feeds/All', {
      dataType: 'json',
      success: function(data, statusText, xhr) {
        feeds = data;
        feeds.sort(function(a, b) {
          return a.Title.localeCompare(b.Title);
        });
        $.each(feeds, function(i, feed) {
          domain.mungeFeed(feed);
        });
        ui.displayFeeds();
      }
    });
  },

  addFeed: function() {
    $.ajax('/Feeds/Add', {
      dataType: 'json',
      data: { url: $('#addFeedUrl').val() },
      success: function(data, statusText, xhr) {
        if (!data['FoundFeeds']) {
          // leave window open for corrections
          alert('I didn\'t find any feeds :(');
        } else if (data['AddedFeed']) {
          // TODO sorting
          feeds.push(data['AddedFeed']);
          ui.displayFeeds();
          ui.closeFeedPopup();
        } else {
          $('#multifeedOptions').empty();
          $('#addFeedUrl').val(data['DiscoveredFeeds'][0].Uri);
          $.each(data['DiscoveredFeeds'], function(i, feed) {
            $('#multifeedOptions')
              .append($('<option></option>')
                .attr('value', feed.Uri)
                .text(feed.Title));
          });
          $('#multifeed').show();
        }
      }
    })
  },

  markRead: function(feed, article) {
    domain.getSubscription(feed.Id).ReadArticles.push(article.UniqueId);
    $.ajax('/Feeds/MarkRead', {
      dataType: 'json',
      data: {
        feedId: feed.Id,
        articleId: article.UniqueId
      }
    });
  },
  
  initialize: function() {
    // TODO should be something else, no?
    if ($.cookie('.MONOAUTH')) {
      domain.refreshUser();
    } else {
      ui.showLoginWindow();
    }

    // Every 5 minutes
    window.setInterval(domain.refreshUser, 5 * 60 * 1000);
  }
};

var ui = {
  closeFeedPopup: function() {
    $('#addFeedWindow').dialog('close');
  },

  template: function(name, data) {
    var templ = $('script#' + name);
    if (!templ) {
      console.log('template ' + name + ' not found!');
      return 'TEMPLATE ' + name + ' NOT FOUND';
    }

    // Have to trim template text in order not to give jquery a hissy fit.
    return _.template(templ.text(), data)
      .replace(/^\s+/g, '')
      .replace(/\s+$/g, '');
  },

  resizeMainPanel: function() {
    $('#mainPanel').height($(window).height() - $('#headerBar').height());
    $('#mainPanel').width($(window).width());
  },

  updateUserInfos: function() {
    $('#userName').text(user.Email);
  },

  showLoginWindow: function() {
    $('#login_window').dialog({
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
                ui.hideLoginWindow();
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
                hideLoginWindow();
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
    $('#login_window').dialog('close');
  },

  displayFeeds: function() {
    $('.feedList .content').empty();
    $.each(feeds, function(i, feed) {
      var dom = ui.template('feedli', feed);
      $('.feedList .content').append(dom);
    });
  },

  showFeed: function(feedId) {
    var feed = domain.getFeed(feedId);
    if (!feed) return;
    $('.feedli').removeClass('selectedItem');
    $('#feedli_' + feedId).addClass('selectedItem');
    $('#articleList .content').empty();
    $.each(feed.Articles, function(i, article) {
      var dom = ui.template('articleli', {
        article: article,
          feed: feed,
          readClass: article.IsRead ? 'read' : 'unread'
      });
      $('#articleList .content').append(dom);
    });
  },

  showArticle: function(feedId, artId) {
    var feed = domain.getFeed(feedId);
    // TODO error message?
    if (!feed) return;
    var article = domain.getArticle(feed, artId);
    if (!article) return;
    $('.articleli').removeClass('selectedItem');
    var artDiv = $('#' + domain.articleId(feed, article));
    artDiv.addClass('selectedItem');
    artDiv.removeClass('unread');
    artDiv.addClass('read');
    $('#articleView .content').html(ui.template('articlefull', {
      feed: feed,
      article: article
    }));

    if (!article.IsRead) {
      article.IsRead = true;
      domain.markRead(feed, article);
      // TODO update unread count (once we have such a thing)
    }
  },

  initialize: function() {
    ui.resizeMainPanel();
    $(window).resize(ui.resizeMainPanel);
    // This is currently using the jquery ui layout plugin.
    // I have some annoyances with it. Consider switching to something better,
    // or at least simpler, like http://www.methvin.com/splitter/
    bodyLayout = $('#mainPanel').layout({
      defaults: {
        applyDefaultStyles: true,
        resizable: true,
        closable: false,
        slidable: true,
        contentSelector: '.content',
        spacing_open: 4,
        spacing_closed: 4
      },
      south: {
        paneSelector: '.articleView',
        size: 400,
      },
      west: {
        paneSelector: '.feedList'
      },
      center: {
        paneSelector: '.articleList'
      },
    });

    $('#addFeedButton').click(function() {
      $('#multifeed').hide();
      $('#addFeedWindow').dialog({
          height: 'auto',
          width: 'auto',
          buttons: [
              { text: 'Add feed!', click: domain.addFeed },
              { text: 'Maybe later', click: function() { $(this).dialog('close'); } }
          ]
      });
    });
    $('#multifeedOptions').change(function() {
      $('#addFeedUrl').val($('#multifeedOptions').val());
    });
  }
};

var util = {
  hashString: function(str) {
    if (str == null) return 0;
    var hash = 0;
    for (var i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash = hash & hash;
    }
    return Math.abs(hash);
  }
};



$(document).ready(function() {
  ui.initialize();
  domain.initialize();
});
