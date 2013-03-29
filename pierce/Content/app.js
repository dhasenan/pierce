var bodyLayout;
function resizeMainPanel() {
  $('#mainPanel').height($(window).height() - $('#headerBar').height());
  $('#mainPanel').width($(window).width());
}

var user;

function updateUserInfos() {
  $('#userName').text(user.Email);
}

function refreshUser() {
  $.ajax('/Users/Get', {
    dataType: 'json',
    success: function(data, statusText, xhr) {
      user = data;
      updateUserInfos();
      refreshFeeds();
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
  $('#articleView .content').html(ich.articlefull({
    feed: feed,
    article: article
  }));
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
      paneSelector: '.articleView'
    },
    west: {
      paneSelector: '.feedList'
    },
    center: {
      paneSelector: '.articleList'
    },
  });

  $('#login_button').click(function() {
    $('#login_window').dialog('close');
    $.ajax('/Users/Login', {
      dataType: 'json',
      data: {
        'email': $('#email').val(),
        'password': $('#password').val(),
        'register': false
      },
      success: function(data, statusText, xhr) {
        user = data;
        updateUserInfos();
        refreshFeeds();
      }
    });
  });

  if ($.cookie('.MONOAUTH')) {
    refreshUser();
  } else {
    $('#login_window').dialog();
  }

  // Every 5 minutes
  window.setInterval(refreshUser, 5 * 60 * 1000);
});
