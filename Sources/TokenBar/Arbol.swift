import Foundation

enum Arbol {
    /// Arma el árbol de carpetas a partir de las filas agregadas.
    ///
    /// Los tramos intermedios sin uso propio y con un solo hijo se fusionan
    /// (`/Users/yugoxc/Desktop` en vez de tres niveles vacíos), para que abrir
    /// el árbol lleve directo a donde de verdad se gastaron tokens.
    static func construir(_ filas: [FilaUso]) -> NodoArbol {
        let raiz = NodoArbol(id: "", nombre: "Total")
        var indice: [String: NodoArbol] = ["": raiz]

        for fila in filas {
            let ruta = fila.cwd
            let partes = ruta.split(separator: "/").map(String.init)
            var padre = raiz
            var acumulada = ""
            raiz.tokens += fila.tokens

            for parte in partes {
                acumulada += "/" + parte
                let nodo: NodoArbol
                if let existente = indice[acumulada] {
                    nodo = existente
                } else {
                    nodo = NodoArbol(id: acumulada, nombre: parte)
                    indice[acumulada] = nodo
                    padre.hijos.append(nodo)
                }
                nodo.tokens += fila.tokens
                padre = nodo
            }
            padre.propios += fila.tokens
        }

        ordenar(raiz)
        return raiz
    }

    /// Colapsa tramos de paso y ordena de mayor a menor consumo.
    private static func ordenar(_ nodo: NodoArbol) {
        var nuevos: [NodoArbol] = []
        for var hijo in nodo.hijos {
            // Colapsa mientras el hijo sea un simple tramo de paso.
            while hijo.hijos.count == 1, hijo.propios.total == 0, let unico = hijo.hijos[0] as NodoArbol? {
                let fusionado = NodoArbol(id: unico.id, nombre: hijo.nombre + "/" + unico.nombre)
                fusionado.tokens = unico.tokens
                fusionado.propios = unico.propios
                fusionado.hijos = unico.hijos
                hijo = fusionado
            }
            ordenar(hijo)
            nuevos.append(hijo)
        }
        nodo.hijos = nuevos.sorted { $0.tokens.total > $1.tokens.total }
    }
}
