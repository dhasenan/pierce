var user;
var feeds;

var bodyLayout;

function hashString(str) {
  var hash = 0;
  for (var i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash = hash & hash;
  }
  return hash;
}

function resizeMainPanel() {
  $('#mainPanel').height($(window).height() - $('#headerBar').height());
  $('#mainPanel').width($(window).width());
}

function updateUserInfos() {
  $('#userName').text(user.Email);
}

function showLoginWindow() {
  $('#login_window').dialog({ height: 'auto', width: 'auto' });
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
        if (!feed.Articles) {
          console.log('feed ' + feed.Id + ' has no articles');
          return;
        }
        var sub = getSubscription(feed.Id);
        if (!sub) {
          console.log('feed ' + feed.Id + ' has no subscription');
          return;
        }
        $.each(feed.Articles, function(j, article) {
          article.HashId = hashString(article.UniqueId);
          article.IsRead = sub.ReadArticles.indexOf(article.UniqueId) >= 0;
        });
      });
      displayFeeds();
    }
  });
}

function displayFeeds() {
  $('.feedList .content').empty();
  $.each(feeds, function(i, feed) {
    var dom = ich.feedli(feed);
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

function getArticle(feed, articleId) {
  for (var i = 0; i < feed.Articles.length; i++) {
    if (feed.Articles[i].UniqueId == articleId) {
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
    var dom = ich.articleli({
      article: article,
      feed: feed
    });
    $(dom).click(function() {
      // Thanks to $.each, no need for binding hacks.
      // I'd put this in the template, but I'm getting errors when I do so.
      showArticle(feed.Id, article.UniqueId);
    });
    $('#articleList .content').append(dom);
  });
}

function showArticle(feedId, articleId) {
  var feed = getFeed(feedId);
  // TODO error message?
  if (!feed) return;
  var article = getArticle(feed, articleId);
  if (!article) return;
  $('.articleli').removeClass('selectedItem');
  $('#articleli_' + feedId + '_' + article.HashId).addClass('selectedItem');
  $('#articleView .content').html(ich.articlefull({
    feed: feed,
    article: article
  }));

  if (!article.IsRead) {
    article.IsRead = true;
    $.ajax('/Feeds/MarkRead', {
      dataType: 'json',
      data: {
        feedId: feedId,
        articleId: articleId
      }
    });
    // TODO update unread count (once we have such a thing)
  }
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
    $('#addFeedWindow').dialog({ height: 'auto', width: 'auto' });
  });
  $('#addFeedWindowClose').click(function() {
    $('#addFeedWindow').dialog('close');
  });
  $('#addFeedInitialButton').click(function() {
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
  });

  if ($.cookie('.MONOAUTH')) {
    refreshUser();
  } else {
    showLoginWindow();
  }

  // Every 5 minutes
  window.setInterval(refreshUser, 5 * 60 * 1000);
});
