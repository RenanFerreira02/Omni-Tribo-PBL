import { useEffect as mockUseEffect } from 'react';
import { fireEvent, screen } from '@testing-library/react-native';

import Sobre from '../(app)/sobre';
import { render } from '@/testes/render';

const mockSubstituir = jest.fn();

jest.mock('expo-router', () => ({
  useFocusEffect: (efeito: () => void) => mockUseEffect(efeito, [efeito]),
  useRouter: () => ({ push: jest.fn(), replace: mockSubstituir, back: jest.fn() }),
  useLocalSearchParams: () => ({}),
}));

beforeEach(() => {
  mockSubstituir.mockClear();
});

/**
 * Tela "Sobre".
 *
 * <p>Dois testes com propósitos diferentes. O primeiro é de PRODUTO: a tese social precisa estar em
 * tela, porque é a única resposta do app para "para que isto serve". O segundo é de CONTRATO com o
 * enunciado da fase, que exige `Image` e `Button` do react-native — e um teste que os alcança pelo
 * `testID` reprova se alguém os trocar por `Pressable` numa futura padronização de design system.
 */
describe('Tela Sobre', () => {
  it('enuncia a tese social e mostra a marca', async () => {
    await render(<Sobre />);

    expect(screen.getByText(/Vizinho ajuda vizinho/i)).toBeTruthy();
    expect(screen.getByText(/tokens são reconhecimento, não dinheiro/i)).toBeTruthy();
    // A entrega falida aparece como UM caso, não como a tese — a ordem importa e é o que a virada
    // social desta fase mudou.
    expect(screen.getByText(/também vira\s+missão/i)).toBeTruthy();
    expect(screen.getByTestId('logo-omnitribo')).toBeTruthy();
  });

  it('o botão leva de volta às missões', async () => {
    await render(<Sobre />);

    await fireEvent.press(screen.getByTestId('botao-ver-missoes'));

    expect(mockSubstituir).toHaveBeenCalledWith('/(tabs)');
  });
});
