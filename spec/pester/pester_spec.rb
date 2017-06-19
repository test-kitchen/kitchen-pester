require_relative '..\..\lib\kitchen\verifier\Pester'

class MockPester < Kitchen::Verifier::Pester
    def sandbox_path
        'C:/users/jdoe/temp/kitchen-temp'
    end
    def suite_test_folder
        'C:/lowercasedpath/Pester/tests'
    end
end

describe 'when sandboxifying a path' do
    let(:sandboxifiedPath) {
        pester = MockPester.new
        pester.sandboxify_path('C:/LOWERcasedpath/Pester/tests/test')
    }

    it 'should ignore case' do
        expect(sandboxifiedPath).to eq 'C:/users/jdoe/temp/kitchen-temp/test'
    end
end
