enum Flavor { stable, beta }

class F {
  static late final Flavor appFlavor;

  static String get name => appFlavor.name;

  static String get title {
    switch (appFlavor) {
      case Flavor.stable:
        return 'Noctua';
      case Flavor.beta:
        return 'Noctua Beta';
    }
  }
}
