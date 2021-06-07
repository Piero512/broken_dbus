import 'package:broken_dbus/src/constants.dart';
import 'package:broken_dbus/src/entry_group.dart';
import 'package:broken_dbus/src/server.dart';
import 'package:broken_dbus/src/service_browser.dart';
import 'package:dbus/dbus.dart';

void dbgPrint(String str) {
  print('DEBUG: $str');
}

extension ItemNewPrintHelpers on AvahiServiceBrowserItemNew {
  String get friendlyString {
    return "AvahiServiceBrowserItemNew(path: '$path',interface: '$interfaceValue',protocol: '${protocol.toAvahiProtocol().toString()}', name: '$name',type: '$type',domain: '$domain'";
  }
}

extension ItemRemovePrintHelpers on AvahiServiceBrowserItemRemove {
  String get friendlyString {
    return "AvahiServiceBrowserItemRemove(path: '$path',interface: '$interfaceValue',protocol: '${protocol.toAvahiProtocol().toString()}', name: '$name',type: '$type',domain: '$domain'";
  }
}

extension ResoveServicePrintHelpers on AvahiServerResolvedService {
  String get friendlyString {
    return 'AvahiServerResolvedService(interface: $interface, protocol: $protocol, name: $name, type: $type, domain: $domain, host: $host, answerProtocol: $aprotocol, address: $address, port: $port, flags: $flags, txt: $txt';
  }
}

Future<void> resolveService(
    AvahiServer server, AvahiServiceBrowserItemNew newService) async {
  dbgPrint('DBG: ${newService.friendlyString}');
  var reply = AvahiServerResolvedService(await server.callResolveService(
      interface: newService.interfaceValue,
      protocol: newService.protocol,
      name: newService.name,
      type: newService.type,
      domain: newService.domain,
      answerProtocol: AvahiProtocolUnspecified,
      flags: 0));
  dbgPrint('Service Resolved!');
  dbgPrint(reply.friendlyString);
}

Future<void> main(List<String> arguments) async {
  var client = DBusClient.system();
  var avahiServer =
      AvahiServer(client, 'org.freedesktop.Avahi', DBusObjectPath('/'));
  var entryGroup = AvahiEntryGroup(client, 'org.freedesktop.Avahi',
      DBusObjectPath(await avahiServer.callEntryGroupNew()));
  // Announce a random service;
  var type2 = '_brokendbus._tcp';
  await entryGroup.callAddService(
      interface: AvahiIfIndexUnspecified,
      protocol: AvahiProtocolUnspecified,
      flags: 0,
      name: 'Test service for broken_dbus',
      type: type2,
      domain: '',
      host: '',
      port: 3000,
      txt: []);
  await entryGroup.callCommit();
  await entryGroup.stateChanged.firstWhere((event) =>
      event.state ==
      AvahiEntryGroupState.AVAHI_ENTRY_GROUP_ESTABLISHED.toInt());
  // Since the issue reproduces on Ubuntu 20.04 with Avahi < 0.8
  // I'm just including the code that establishes the workaround.
  var workaroundSub = DBusSignalStream(client,
          sender: 'org.freedesktop.Avahi',
          interface: 'org.freedesktop.Avahi.ServiceBrowser',
          name: 'ItemNew')
      .listen((event) =>
          resolveService(avahiServer, AvahiServiceBrowserItemNew(event)));
  var serviceBrowser = AvahiServiceBrowser(
      client,
      'org.freedesktop.Avahi',
      DBusObjectPath(await avahiServer.callServiceBrowserNew(
          AvahiIfIndexUnspecified, AvahiProtocolUnspecified, type2, '', 0)));
  var regularSub = serviceBrowser.itemNew
      .listen((event) => resolveService(avahiServer, event));
  await Future.delayed(Duration(seconds: 20));
  await workaroundSub.cancel();
  await regularSub.cancel();
  await entryGroup.callFree();
}
