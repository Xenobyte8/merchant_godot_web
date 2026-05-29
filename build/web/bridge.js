/**
 * bridge.js — JS-мост между Yandex Games SDK и GDScript (Godot 4).
 *
 * Доступен из GDScript через:
 *   var bridge = JavaScriptBridge.get_interface("ysdk_bridge")
 *
 * Все методы безопасны при отсутствии SDK (window.ysdk == null):
 * в этом случае callback вызывается с null/false.
 */
(function () {
  'use strict';

  window.ysdk_bridge = {

    /** Возвращает true, если SDK уже инициализирован. */
    isReady: function () {
      return !!(window.ysdk);
    },

    /**
     * Сигнализирует платформе, что игра загружена и готова к игровому процессу.
     * Вызывать один раз после полной загрузки сцены.
     */
    signalLoaded: function () {
      if (window.ysdk &&
          window.ysdk.features &&
          window.ysdk.features.LoadingAPI) {
        window.ysdk.features.LoadingAPI.ready();
      }
      // Скрываем лоадер вне зависимости от наличия SDK
      var loader = document.getElementById('game-loader');
      if (loader) {
        loader.classList.add('hidden');
        setTimeout(function () { loader.remove(); }, 450);
      }
    },

    /**
     * Получает данные текущего игрока.
     * callback вызывается с объектом { unique_id, name, is_authorized }
     * или null при ошибке / отсутствии SDK.
     *
     * @param {Function} callback
     */
    getPlayer: function (callback) {
      if (!window.ysdk) {
        callback(null);
        return;
      }
      window.ysdk.getPlayer({ scopes: false })
        .then(function (player) {
          callback({
            unique_id: player.getUniqueID(),
            name: player.getName() || '',
            is_authorized: player.getMode() !== 'lite'
          });
        })
        .catch(function (e) {
          console.warn('[YaSDK] getPlayer failed:', e);
          callback(null);
        });
    },

    /**
     * Записывает очки игрока в лидерборд.
     * callback(true/false) — результат операции.
     *
     * @param {string}   leaderboard_name  Имя лидерборда из консоли разработчика
     * @param {number}   score             Целое число
     * @param {Function} callback
     */
    setLeaderboardScore: function (leaderboard_name, score, callback) {
      if (!window.ysdk) {
        if (callback) callback(false);
        return;
      }
      window.ysdk.getLeaderboards()
        .then(function (lb) {
          return lb.setLeaderboardScore(leaderboard_name, Math.floor(score));
        })
        .then(function () {
          if (callback) callback(true);
        })
        .catch(function (e) {
          console.warn('[YaSDK] setLeaderboardScore failed:', e);
          if (callback) callback(false);
        });
    }

  };
})();
