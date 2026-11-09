# Neutrin Browser

Un navegador para iOS, más tranquilo, privado y personal. Está hecho en **SwiftUI** y usa **WKWebView**.

![Ícono](NeutrinBrowser/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

## Pantallas

| Pantalla | Qué hace |
|---|---|
| **Inicio** | Logo, buscador (dirección o búsqueda), escáner de QR, 8 accesos rápidos, Favoritos y Recientes. |
| **Navegador** | Página web a pantalla completa con barra flotante "glass": atrás/adelante, dirección con candado, compartir, pestañas y menú (recargar, favoritos, copiar enlace, nueva pestaña, cerrar). Incluye barra de progreso y gestos de deslizar para ir atrás o adelante. |
| **Tabs & Spaces** | Pestañas agrupadas por *Spaces* (Personal, Trabajo, Estudio…), con miniaturas reales de cada página, búsqueda de pestañas y creación, edición o borrado de spaces. |

Las pestañas, los spaces, los favoritos, el historial y el buscador elegido se guardan en el dispositivo como JSON.

## Requisitos

- Xcode 16 o posterior
- iOS 17 o posterior

## Cómo ejecutarlo

1. Abre `NeutrinBrowser.xcodeproj` en Xcode.
2. Elige tu equipo en *Signing & Capabilities* (o usa el simulador).
3. Pulsa ▶︎ Run.

## Estructura

```
NeutrinBrowser/
├── App/            Punto de entrada y RootView (inicio ↔ navegador)
├── Models/         Space, Tab, Favorite, History, SearchEngine, URLResolver
├── Store/          BrowserStore (estado + persistencia), TabController (WKWebView)
├── Views/          HomeView, BrowserView, TabsSpacesView, hojas, escáner QR
├── DesignSystem/   Colores, efecto glass, logo vectorial, ilustraciones
└── Assets.xcassets
```
