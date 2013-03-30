var user;
var feeds;

var bodyLayout;

function articleId(feed, article) {
  return 'articleli_' + feed.Id + '_' + article.HashId;
}

function template(name, data) {
  var templ = $('script#' + name);
  if (!templ) {
    console.log('template ' + name + ' not found!');
    return 'TEMPLATE ' + name + ' NOT FOUND';
  }

  // Have to trim template text in order not to give jquery a hissy fit.
  return _.template(templ.text(), data)
      .replace(/^\s+/g, '')
      .replace(/\s+$/g, '');
}

function hashString(str) {
  if (str == null) return 0;
  var hash = 0;
  for (var i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash = hash & hash;
  }
  return Math.abs(hash);
}

function resizeMainPanel() {
  $('#mainPanel').height($(window).height() - $('#headerBar').height());
  $('#mainPanel').width($(window).width());
}

function updateUserInfos() {
  $('#userName').text(user.Email);
}

function showLoginWindow() {
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
                hideLoginWindow();
                user = data;
                updateUserInfos();
                refreshFeeds();
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
                updateUserInfos();
                refreshFeeds();
              }
            });
          }
        },
    ]
  });
}

function hideLoginWindow() {
  $('#login_window').dialog('close');
}

function refreshUser() {
  $.ajax('/Users/Get', {
    dataType: 'json',
    success: function(data, statusText, xhr) {
      user = data;
      updateUserInfos();
      refreshFeeds();
    },
    error: function() {
      showLoginWindow();
    }
  });
}

function jsDate(aspNetDate) {
  return new Date(parseInt(aspNetDate.substr(6)));
}

function mungeFeed(feed) {
  feed.LastRead = jsDate(feed.LastRead);
  feed.NextRead = jsDate(feed.NextRead);
  feed.ReadInterval = feed.ReadInterval.TotalSeconds;
  var sub = getSubscription(feed.Id);
  if (!sub) {
    console.log('feed ' + feed.Id + ' has no subscription');
    return;
  }
  $.each(feed.Articles, function(i, art) {
    art.PublishDate = jsDate(art.PublishDate);
    art.HashId = hashString(art.UniqueId);
    if (sub) {
      art.IsRead = sub.ReadArticles.indexOf(art.UniqueId) >= 0;
    }
  });
}

function getSubscription(feedId) {
  if (!user.Subscriptions) return;
  for (var i = 0; i < user.Subscriptions.length; i++) {
    if (user.Subscriptions[i].FeedId == feedId) {
      return user.Subscriptions[i];
    }
  }
  return null;
}

function refreshFeeds() {
  $.ajax('/Feeds/All', {
    dataType: 'json',
    success: function(data, statusText, xhr) {
      feeds = data;
      $.each(feeds, function(i, feed) {
        mungeFeed(feed);
      });
      displayFeeds();
    }
  });
}

function displayFeeds() {
  $('.feedList .content').empty();
  feeds.sort(function(a, b) {
    return 
  });
  $.each(feeds, function(i, feed) {
    var dom = template('feedli', feed);
    $(dom).click(function() {
      showFeed(feed.Id);
    })
    $('.feedList .content').append(dom);
  });
}

function getFeed(feedId) {
  for (var i = 0; i < feeds.length; i++) {
    if (feeds[i].Id == feedId) {
      return feeds[i];
    }
  }
  return null;
}

function getArticle(feed, artId) {
  for (var i = 0; i < feed.Articles.length; i++) {
    if (feed.Articles[i].HashId == artId) {
      return feed.Articles[i];
    }
  }
  return null;
}

function showFeed(feedId) {
  var feed = getFeed(feedId);
  if (!feed) return;
  $('.feedli').removeClass('selectedItem');
  $('#feedli_' + feedId).addClass('selectedItem');
  $('#articleList .content').empty();
  $.each(feed.Articles, function(i, article) {
    var dom = template('articleli', {
      article: article,
      feed: feed,
      readClass: article.IsRead ? 'read' : 'unread'
    });
    $('#articleList .content').append(dom);
  });
}

function showArticle(feedId, artId) {
  var feed = getFeed(feedId);
  // TODO error message?
  if (!feed) return;
  var article = getArticle(feed, artId);
  if (!article) return;
  $('.articleli').removeClass('selectedItem');
  var artDiv = $('#' + articleId(feed, article));
  artDiv.addClass('selectedItem');
  artDiv.removeClass('unread');
  artDiv.addClass('read');
  $('#articleView .content').html(template('articlefull', {
    feed: feed,
    article: article
  }));

  if (!article.IsRead) {
    article.IsRead = true;
    getSubscription(feedId).ReadArticles.push(article.UniqueId);
    $.ajax('/Feeds/MarkRead', {
      dataType: 'json',
      data: {
        feedId: feedId,
        articleId: article.UniqueId
      }
    });
    // TODO update unread count (once we have such a thing)
  }
}

function addFeed() {
    $.ajax('/Feeds/Add', {
      dataType: 'json',
      data: { url: $('#addFeedUrl').val() },
      success: function(data, statusText, xhr) {
        if (!data['FoundFeeds']) {
          // leave window open for corrections
          alert('I didn\'t find any feeds :(');
        } else if (data['AddedFeed']) {
          // TODO sorting
          feeds[feeds.length] = data['AddedFeed'];
          displayFeeds();
          $('#addFeedWindow').dialog('close');
        } else {
          // TODO select between them, leave dialog open
          alert('Multiple feeds detected!');
          $('#addFeedWindow').dialog('close');
        }
      }
    })
}

$(document).ready(function() {
  resizeMainPanel();
  $(window).resize(resizeMainPanel);
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

  $('#register_button').click(function() {
    $.ajax('/Users/Register', {
      dataType: 'json',
      data: {
        'email': $('#email').val(),
        'password': $('#password').val(),
      },
      success: function(data, statusText, xhr) {
        hideLoginWindow();
        user = data;
        updateUserInfos();
        refreshFeeds();
      }
    });
  });

  $('#login_button').click(function() {
    $.ajax('/Users/Login', {
      dataType: 'json',
      data: {
        'email': $('#email').val(),
        'password': $('#password').val(),
      },
      success: function(data, statusText, xhr) {
        hideLoginWindow();
        user = data;
        updateUserInfos();
        refreshFeeds();
      }
    });
  });

  $('#addFeedButton').click(function() {
    $('#addFeedWindow').dialog({
        height: 'auto',
        width: 'auto',
        buttons: [
            { text: 'Add feed!', click: addFeed },
            { text: 'Maybe later', click: function() { $(this).dialog('close'); } }
        ]
    });
  });
  $('#addFeedWindowClose').click(function() {
    $('#addFeedWindow').dialog('close');
  });

  if ($.cookie('.MONOAUTH')) {
    refreshUser();
  } else {
    showLoginWindow();
  }

  // Every 5 minutes
  window.setInterval(refreshUser, 5 * 60 * 1000);
});
