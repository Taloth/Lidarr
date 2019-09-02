import $ from 'jquery';
import * as signalRFramework from 'signalr';
import * as signalRCore from '@aspnet/signalr/dist/browser/signalr.js';
import PropTypes from 'prop-types';
import { Component } from 'react';
import { connect } from 'react-redux';
import { createSelector } from 'reselect';
import { repopulatePage } from 'Utilities/pagePopulator';
import titleCase from 'Utilities/String/titleCase';
import { fetchCommands, updateCommand, finishCommand } from 'Store/Actions/commandActions';
import { setAppValue, setVersion } from 'Store/Actions/appActions';
import { update, updateItem, removeItem } from 'Store/Actions/baseActions';
import { fetchArtist } from 'Store/Actions/artistActions';
import { fetchHealth } from 'Store/Actions/systemActions';
import { fetchQueue, fetchQueueDetails } from 'Store/Actions/queueActions';
import { fetchRootFolders } from 'Store/Actions/rootFolderActions';
import { fetchTags, fetchTagDetails } from 'Store/Actions/tagActions';

function getState(status) {
  switch (status) {
    case 0:
      return 'connecting';
    case 1:
      return 'connected';
    case 2:
      return 'reconnecting';
    case 4:
      return 'disconnected';
    default:
      throw new Error(`invalid status ${status}`);
  }
}

function isAppDisconnected(disconnectedTime) {
  if (!disconnectedTime) {
    return false;
  }

  return Math.floor(new Date().getTime() / 1000) - disconnectedTime > 180;
}

function getHandlerName(name) {
  name = titleCase(name);
  name = name.replace('/', '');

  return `handle${name}`;
}

function createMapStateToProps() {
  return createSelector(
    (state) => state.app.isReconnecting,
    (state) => state.app.isDisconnected,
    (state) => state.queue.paged.isPopulated,
    (isReconnecting, isDisconnected, isQueuePopulated) => {
      return {
        isReconnecting,
        isDisconnected,
        isQueuePopulated
      };
    }
  );
}

const mapDispatchToProps = {
  dispatchFetchCommands: fetchCommands,
  dispatchUpdateCommand: updateCommand,
  dispatchFinishCommand: finishCommand,
  dispatchSetAppValue: setAppValue,
  dispatchSetVersion: setVersion,
  dispatchUpdate: update,
  dispatchUpdateItem: updateItem,
  dispatchRemoveItem: removeItem,
  dispatchFetchArtist: fetchArtist,
  dispatchFetchHealth: fetchHealth,
  dispatchFetchQueue: fetchQueue,
  dispatchFetchQueueDetails: fetchQueueDetails,
  dispatchFetchRootFolders: fetchRootFolders,
  dispatchFetchTags: fetchTags,
  dispatchFetchTagDetails: fetchTagDetails
};

class SignalRConnector extends Component {

  //
  // Lifecycle

  constructor(props, context) {
    super(props, context);

    this.connectionOptions = { transport: ['webSockets', 'serverSentEvents', 'longPolling'] };
    this.connection = null;
    this.retryInterval = 1;
    this.retryTimeoutId = null;
    this.disconnectedTime = null;
  }

  componentDidMount() {
    console.log('[signalR] starting');

    if (this.props.isNetCore || true) {
      this.createSignalRCoreConnection();
    } else {
      this.createSignalRFrameworkConnection();
    }

  }

  componentWillUnmount() {
    this.connection.stop();
    this.connection = null;
  }

  //
  // Control

  createSignalRCoreConnection = () => {
    const url = `${window.Lidarr.urlBase}/signalr/messages`;

    this.connection = new signalRCore.HubConnectionBuilder()
      .withUrl(url, {
        accessTokenFactory: () => {
          return window.Lidarr.apiKey;
        }
      })
      .build();

    this.connection.onclose(this.onClose);
    this.connection.on('receiveMessage', this.onReceiveMessage);

    this.connection.start()
      .then(this.onConnected)
      .catch(this.onError);
  };

  createSignalRFrameworkConnection = () => {
    const url = `${window.Lidarr.urlBase}/signalr`;

    this.connection = $.connection(url, { apiKey: window.Lidarr.apiKey });

    this.connection.stateChanged(this.onStateChanged);
    this.connection.received(this.onReceiveMessage);
    this.connection.reconnecting(this.onReconnecting);
    this.connection.disconnected(this.onClose);

    this.connection.start(this.connectionOptions);
  };

  retryConnection = () => {
    const attrs = {
      isReconnecting: true
    };

    if (isAppDisconnected(this.disconnectedTime)) {
      attrs.isConnected = false;
      attrs.isDisconnected = true;
    }

    setAppValue(attrs);

    this.retryTimeoutId = setTimeout(() => {
      this.startConnection();
      this.retryInterval = Math.min(this.retryInterval + 1, 10);
    }, this.retryInterval * 1000);
  }

  handleMessage = (message) => {
    const {
      name,
      body
    } = message;

    const handler = this[getHandlerName(name)];

    if (handler) {
      handler(body);
      return;
    }

    console.error(`signalR: Unable to find handler for ${name}`);
  }

  handleCalendar = (body) => {
    if (body.action === 'updated') {
      this.props.dispatchUpdateItem({
        section: 'calendar',
        updateOnly: true,
        ...body.resource
      });
    }
  }

  handleCommand = (body) => {
    if (body.action === 'sync') {
      this.props.dispatchFetchCommands();
      return;
    }

    const resource = body.resource;
    const status = resource.status;

    // Both sucessful and failed commands need to be
    // completed, otherwise they spin until they timeout.

    if (status === 'completed' || status === 'failed') {
      this.props.dispatchFinishCommand(resource);
    } else {
      this.props.dispatchUpdateCommand(resource);
    }
  }

  handleAlbum = (body) => {
    if (body.action === 'updated') {
      this.props.dispatchUpdateItem({
        section: 'albums',
        updateOnly: true,
        ...body.resource
      });
    }
  }

  handleTrack = (body) => {
    if (body.action === 'updated') {
      this.props.dispatchUpdateItem({
        section: 'tracks',
        updateOnly: true,
        ...body.resource
      });
    }
  }

  handleTrackfile = (body) => {
    const section = 'trackFiles';

    if (body.action === 'updated') {
      this.props.dispatchUpdateItem({ section, ...body.resource });
    } else if (body.action === 'deleted') {
      this.props.dispatchRemoveItem({ section, id: body.resource.id });
    }

    // Repopulate the page to handle recently imported file
    repopulatePage('trackFileUpdated');
  }

  handleHealth = () => {
    this.props.dispatchFetchHealth();
  }

  handleArtist = (body) => {
    const action = body.action;
    const section = 'artist';

    if (action === 'updated') {
      this.props.dispatchUpdateItem({ section, ...body.resource });
    } else if (action === 'deleted') {
      this.props.dispatchRemoveItem({ section, id: body.resource.id });
    }
  }

  handleQueue = () => {
    if (this.props.isQueuePopulated) {
      this.props.dispatchFetchQueue();
    }
  }

  handleQueueDetails = () => {
    this.props.dispatchFetchQueueDetails();
  }

  handleQueueStatus = (body) => {
    this.props.dispatchUpdate({ section: 'queue.status', data: body.resource });
  }

  handleVersion = (body) => {
    const version = body.Version;

    this.props.dispatchSetVersion({ version });
  }

  handleWantedCutoff = (body) => {
    if (body.action === 'updated') {
      this.props.dispatchUpdateItem({
        section: 'cutoffUnmet',
        updateOnly: true,
        ...body.resource
      });
    }
  }

  handleWantedMissing = (body) => {
    if (body.action === 'updated') {
      this.props.dispatchUpdateItem({
        section: 'missing',
        updateOnly: true,
        ...body.resource
      });
    }
  }

  handleSystemTask = () => {
    // No-op for now, we may want this later
  }

  handleRootfolder = () => {
    this.props.dispatchFetchRootFolders();
  }

  handleTag = (body) => {
    if (body.action === 'sync') {
      this.props.dispatchFetchTags();
      this.props.dispatchFetchTagDetails();
      return;
    }
  }

  //
  // Listeners

  onStateChanged = (change) => {
    const state = getState(change.newState);
    console.log(`[signalR] ${state}`);

    if (state === 'connected') {
      this.onConnected();
    }
  }

  onConnected = () => {
    console.debug('[signalR] connected');

    // Clear disconnected time
    this.disconnectedTime = null;

    const {
      dispatchFetchCommands,
      dispatchFetchArtist,
      dispatchSetAppValue
    } = this.props;

    // Repopulate the page (if a repopulator is set) to ensure things
    // are in sync after reconnecting.

    if (this.props.isReconnecting || this.props.isDisconnected) {
      dispatchFetchArtist();
      dispatchFetchCommands();
      repopulatePage();
    }

    dispatchSetAppValue({
      isConnected: true,
      isReconnecting: false,
      isDisconnected: false,
      isRestarting: false
    });

    this.retryInterval = 5;

    if (this.retryTimeoutId) {
      clearTimeout(this.retryTimeoutId);
    }
  }

  onReceiveMessage = (message) => {
    console.debug('[signalR] received', message.name, message.body);

    this.handleMessage(message);
  }

  onReconnecting = () => {
    if (window.Lidarr.unloading) {
      return;
    }

    if (!this.disconnectedTime) {
      this.disconnectedTime = Math.floor(new Date().getTime() / 1000);
    }

    this.props.dispatchSetAppValue({
      isReconnecting: true
    });
  }

  onClose = () => {
    console.debug('[signalR] connection closed');

    if (window.Lidarr.unloading) {
      return;
    }

    if (!this.disconnectedTime) {
      this.disconnectedTime = Math.floor(new Date().getTime() / 1000);
    }

    this.retryConnection();
  }

  onError = () => {
    console.debug('[signalR] connection error');

    if (window.Lidarr.unloading) {
      return;
    }

    if (!this.disconnectedTime) {
      this.disconnectedTime = Math.floor(new Date().getTime() / 1000);
    }

    this.retryConnection();
  }

  //
  // Render

  render() {
    return null;
  }
}

SignalRConnector.propTypes = {
  isNetCore: PropTypes.bool.isRequired,
  isReconnecting: PropTypes.bool.isRequired,
  isDisconnected: PropTypes.bool.isRequired,
  isQueuePopulated: PropTypes.bool.isRequired,
  dispatchFetchCommands: PropTypes.func.isRequired,
  dispatchUpdateCommand: PropTypes.func.isRequired,
  dispatchFinishCommand: PropTypes.func.isRequired,
  dispatchSetAppValue: PropTypes.func.isRequired,
  dispatchSetVersion: PropTypes.func.isRequired,
  dispatchUpdate: PropTypes.func.isRequired,
  dispatchUpdateItem: PropTypes.func.isRequired,
  dispatchRemoveItem: PropTypes.func.isRequired,
  dispatchFetchArtist: PropTypes.func.isRequired,
  dispatchFetchHealth: PropTypes.func.isRequired,
  dispatchFetchQueue: PropTypes.func.isRequired,
  dispatchFetchQueueDetails: PropTypes.func.isRequired,
  dispatchFetchRootFolders: PropTypes.func.isRequired,
  dispatchFetchTags: PropTypes.func.isRequired,
  dispatchFetchTagDetails: PropTypes.func.isRequired
};

export default connect(createMapStateToProps, mapDispatchToProps)(SignalRConnector);
