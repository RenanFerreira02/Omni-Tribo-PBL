import Constants from 'expo-constants';
import { useRouter } from 'expo-router';
import { Button, Image, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { TituloTela } from '@/components/TituloTela';
import { cores, espaco, raio, textoAcessivel, tipografia } from '@/theme';

/**
 * Tela "Sobre": a tese do produto, dita ao usuário dentro do app.
 *
 * <p><b>Por que ela existe, e por que aqui.</b> O app explica missões, carteira e benefícios, mas
 * em lugar nenhum dizia PARA QUE ele serve. Quem instala pelo convite de um vizinho abre o radar e
 * vê uma lista de tarefas sem saber que está entrando numa economia de cuidado do bairro. O
 * onboarding diz isso uma vez e nunca mais; esta tela é onde a resposta fica disponível depois.
 *
 * <p><b>Sobre os componentes.</b> É a única tela do app que usa {@code Image} e {@code Button}
 * direto do react-native. O padrão do design system é {@code Botao} (sobre {@code Pressable}),
 * porque o {@code Button} do RN não aceita estilo — e é justamente por ser sem estilo que ele não
 * destoa aqui, numa tela de créditos, enquanto destoaria numa tela de missão. Não copie este par
 * para as outras telas.
 */
export default function Sobre() {
  const router = useRouter();
  const versao = Constants.expoConfig?.version ?? '—';

  return (
    <SafeAreaView style={estilos.raiz} testID="tela-sobre">
      <ScrollView contentContainerStyle={estilos.conteudo}>
        <View style={estilos.marca}>
          {/* Image do react-native. `accessibilityLabel` e não `alt`: leitor de tela do RN lê o
              primeiro; a imagem é decorativa do ponto de vista da tarefa, mas identifica o app. */}
          <Image
            source={require('../../assets/images/icon.png')}
            style={estilos.logo}
            resizeMode="contain"
            accessibilityLabel="Marca do Omni-Tribo"
            testID="logo-omnitribo"
          />
          <TituloTela>Omni-Tribo</TituloTela>
          <Text style={estilos.versao}>Versão {versao}</Text>
        </View>

        <Text style={estilos.tese}>Vizinho ajuda vizinho, e o bairro remunera esse cuidado.</Text>

        <View style={estilos.bloco}>
          <Text style={estilos.paragrafo}>
            O Omni-Tribo transforma pedidos de ajuda em missões de bairro. Alguém precisa de uma mão
            para montar um móvel, o mutirão da rua precisa de gente, os recicláveis precisam sair
            daqui — e o vizinho que atende recebe XP e tokens da comunidade.
          </Text>
          <Text style={estilos.paragrafo}>
            Os tokens são reconhecimento, não dinheiro: circulam entre vizinhos da mesma tribo e são
            trocados por benefícios de parceiros do bairro. Nenhum valor em reais passa de uma
            pessoa para outra.
          </Text>
          <Text style={estilos.paragrafo}>
            O pote de cada missão é formado por quem quer que ela aconteça: outros vizinhos da
            tribo, ou um apoiador do bairro. Quem cria a missão não paga — e quem executa recebe
            exatamente o token que alguém pôs ali.
          </Text>
        </View>

        <View style={estilos.acao}>
          {/* Button do react-native. Sem prop `color`: a cor default do sistema é suficiente numa
              tela de créditos, e passar um token de marca aqui esbarraria na regra de lint que
              reserva `cores.*` a preenchimento. */}
          <Button
            title="Ver missões perto de mim"
            onPress={() => router.replace('/(tabs)')}
            testID="botao-ver-missoes"
          />
        </View>

        <Text style={estilos.rodape}>
          Projeto acadêmico FIAP — Sistemas de Informação · RM 555833
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const estilos = StyleSheet.create({
  raiz: { flex: 1, backgroundColor: cores.papel },
  conteudo: { padding: espaco.lg, gap: espaco.lg },
  marca: { alignItems: 'center', gap: espaco.xs },
  logo: { width: 88, height: 88, borderRadius: raio.md },
  versao: { ...tipografia.legenda, color: textoAcessivel.suave },
  tese: {
    ...tipografia.subtitulo,
    color: cores.verdeEscuro,
    textAlign: 'center',
    paddingHorizontal: espaco.sm,
  },
  bloco: { gap: espaco.md },
  paragrafo: { ...tipografia.corpo, color: cores.tinta70 },
  acao: { paddingVertical: espaco.sm },
  rodape: { ...tipografia.legenda, color: textoAcessivel.suave, textAlign: 'center' },
});
