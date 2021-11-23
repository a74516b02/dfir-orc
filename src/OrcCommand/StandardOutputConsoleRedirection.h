//
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright © 2021 ANSSI. All Rights Reserved.
//
// Author(s): fabienfl
//
#pragma once

#include <iostream>

#include "Utils/StdStream/StreamRedirector.h"

namespace Orc {
namespace Command {

class StandardOutputConsoleRedirection final
{
public:
    StandardOutputConsoleRedirection();
    ~StandardOutputConsoleRedirection();

    void Enable();
    void Disable();

private:
    std::unique_ptr<std::streambuf> m_streambuf;
    std::unique_ptr<std::wstreambuf> m_wstreambuf;

    std::ostream m_cout;
    StreamRedirector<char> m_redirector;
    std::wostream m_wcout;
    StreamRedirector<wchar_t> m_wredirector;
};

}  // namespace Command
}  // namespace Orc
